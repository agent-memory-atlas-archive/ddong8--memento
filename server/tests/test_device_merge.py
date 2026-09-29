"""Merging device records left behind by a changed device id.

The plan tests are pure. The merge itself runs against a real PostgreSQL when
MEMENTO_TEST_DATABASE_URL points at a throwaway database (it creates and drops
the schema), e.g. postgresql+asyncpg://postgres@localhost:5433/memento_merge_test
"""

from __future__ import annotations

import os
import sys
import unittest
import uuid
from datetime import datetime, timedelta, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "server"))

from server.db.models import Machine  # noqa: E402
from server.services.device_merge import plan_merges  # noqa: E402

NOW = datetime.now(timezone.utc)


def _m(name: str, user: uuid.UUID | None, beat_days_ago: float | None, merged_into=None) -> Machine:
    return Machine(
        id=uuid.uuid4(),
        name=name,
        collector_token_hash=uuid.uuid4().hex,
        user_id=user,
        last_heartbeat=None if beat_days_ago is None else NOW - timedelta(days=beat_days_ago),
        created_at=NOW - timedelta(days=30),
        merged_into=merged_into,
    )


class PlanTests(unittest.TestCase):
    def test_same_user_same_computer_keeps_the_latest(self) -> None:
        u = uuid.uuid4()
        old, older, current = _m("mini.local (Darwin)", u, 14), _m("mini.local", u, 20), _m("mini.local (Darwin)", u, 0)
        other = _m("laptop (Darwin)", u, 0)
        [(keep, fold)] = plan_merges([old, older, current, other])
        self.assertIs(keep, current)
        self.assertEqual({m.id for m in fold}, {old.id, older.id})

    def test_other_users_and_merged_rows_are_left_alone(self) -> None:
        a, b = uuid.uuid4(), uuid.uuid4()
        rows = [_m("mini.local", a, 1), _m("mini.local", b, 1), _m("mini.local", a, 5, merged_into=uuid.uuid4()), _m("mini.local", None, 0)]
        self.assertEqual(plan_merges(rows), [])

    def test_never_seen_record_loses_to_one_with_a_heartbeat(self) -> None:
        u = uuid.uuid4()
        silent, seen = _m("pc (Windows)", u, None), _m("pc (Windows)", u, 3)
        [(keep, fold)] = plan_merges([silent, seen])
        self.assertIs(keep, seen)
        self.assertEqual(fold, [silent])


DB_URL = os.environ.get("MEMENTO_TEST_DATABASE_URL")


@unittest.skipUnless(DB_URL, "set MEMENTO_TEST_DATABASE_URL to a throwaway PostgreSQL database")
class MergeIntegrationTests(unittest.IsolatedAsyncioTestCase):
    async def asyncSetUp(self) -> None:
        from sqlalchemy import text
        from sqlalchemy.ext.asyncio import async_sessionmaker, create_async_engine

        from server.db.models import Base

        self.engine = create_async_engine(DB_URL)
        async with self.engine.begin() as conn:
            await conn.execute(text("CREATE EXTENSION IF NOT EXISTS vector"))
            await conn.run_sync(Base.metadata.drop_all)
            await conn.run_sync(Base.metadata.create_all)
        self.Session = async_sessionmaker(self.engine, expire_on_commit=False)

    async def asyncTearDown(self) -> None:
        from server.db.models import Base

        async with self.engine.begin() as conn:
            await conn.run_sync(Base.metadata.drop_all)
        await self.engine.dispose()

    async def test_merge_moves_rows_marks_and_audits(self) -> None:
        from sqlalchemy import func, select

        from server.db.models import DeviceTask, Document, MachineMerge, SyncState, Tool, User
        from server.services.device_merge import merge_duplicate_machines
        from server.services.device_service import ensure_device

        async with self.Session() as db:
            user = User(email="a@example.com", role="owner", status="active")
            db.add_all([user, Tool(id="claude_code", display_name="Claude Code")])
            await db.flush()
            old = Machine(name="mini.local (Darwin)", collector_token_hash="old-id", user_id=user.id, last_heartbeat=NOW - timedelta(days=14))
            cur = Machine(name="mini.local (Darwin)", collector_token_hash="new-id", user_id=user.id, last_heartbeat=NOW)
            db.add_all([old, cur])
            await db.flush()

            def doc(machine: Machine, path: str) -> Document:
                return Document(tool_id="claude_code", machine_id=machine.id, relative_path=path, category="conversation",
                                content_type="jsonl", content_hash="h", file_size_bytes=1)

            db.add_all([doc(old, "a.jsonl"), doc(old, "b.jsonl"), doc(old, "same.jsonl"), doc(cur, "same.jsonl"), doc(cur, "c.jsonl")])
            db.add_all([SyncState(machine_id=old.id, tool_id="claude_code", relative_path="a.jsonl", last_offset=0)])
            db.add(DeviceTask(device_id="old-id", machine_id=old.id, action="shell"))
            await db.commit()
            old_id, cur_id = old.id, cur.id

        async with self.Session() as db:
            merged = await merge_duplicate_machines(db)
        self.assertEqual(len(merged), 1)
        self.assertEqual(merged[0]["moved_counts"], {"documents": 2, "sync_state": 1, "device_tasks": 1})
        self.assertEqual(merged[0]["kept_counts"], {"documents": 1, "sync_state": 0})

        async with self.Session() as db:
            count = lambda mid: db.scalar(select(func.count()).select_from(Document).where(Document.machine_id == mid))
            self.assertEqual(await count(cur_id), 4)  # c, same (its own), a, b
            self.assertEqual(await count(old_id), 1)  # its copy of same.jsonl stays, recorded as kept
            self.assertEqual((await db.get(Machine, old_id)).merged_into, cur_id)
            audit = (await db.execute(select(MachineMerge))).scalars().one()
            self.assertEqual(len(audit.moved["documents"]), 2)
            self.assertEqual(audit.collector_token_hash, "old-id")
            # The old device id reporting in again lands on the current record.
            again = await ensure_device(db, "old-id", "mini.local (Darwin)", "Darwin", user_id=None)
            self.assertEqual(again.id, cur_id)

        async with self.Session() as db:
            self.assertEqual(await merge_duplicate_machines(db), [])  # idempotent
