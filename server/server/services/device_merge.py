"""One computer, one device record.

A computer gets a new device id now and then (a new collector, a reset config),
and its old record stays behind holding the files it uploaded first — later
syncs update those files in place, so the computer's data ends up split over
several records and it shows up several times in the device list.

This folds such records into the one the computer uses now: records of the same
user with the same name (platform suffix aside) are merged into the most recently
seen one. Documents, sync state and task history move over; the old record is
kept, marked `merged_into`, and never listed again. Each merge is written to
`machine_merges` with every row it moved, so it can be undone. Idempotent.
"""

from __future__ import annotations

import logging
import time
import uuid
from collections import defaultdict
from datetime import datetime, timezone

from sqlalchemy import select, text, update
from sqlalchemy.ext.asyncio import AsyncSession

from ..db.models import DeviceTask, Document, Machine, MachineMerge, SyncState
from .user_filter import normalize_device_name

log = logging.getLogger("memento.devices")

_LOCK_KEY = 0x6D656D656E746F  # pg advisory lock: only one api instance merges at a time
_BATCH = 200  # rows per UPDATE: re-pointing a document touches all of its indexes


def plan_merges(machines: list[Machine]) -> list[tuple[Machine, list[Machine]]]:
    """(keep, fold) groups: same user and name; keep the most recently seen record."""
    groups: dict[tuple, list[Machine]] = defaultdict(list)
    for m in machines:
        if m.merged_into is not None or m.user_id is None or not normalize_device_name(m.name):
            continue
        groups[(m.user_id, normalize_device_name(m.name))].append(m)
    epoch = datetime.min.replace(tzinfo=timezone.utc)
    plans = []
    for members in groups.values():
        if len(members) < 2:
            continue
        members.sort(key=lambda m: (m.last_heartbeat or epoch, m.created_at or epoch), reverse=True)
        plans.append((members[0], members[1:]))
    return plans


async def _move(db: AsyncSession, model, source: uuid.UUID, target: uuid.UUID) -> tuple[list, list]:
    """Re-point rows of `model` from source to target, except files the target already has."""
    have = {tuple(r) for r in (await db.execute(
        select(model.tool_id, model.relative_path).where(model.machine_id == target)
    )).all()}
    rows = (await db.execute(
        select(model.id, model.tool_id, model.relative_path).where(model.machine_id == source)
    )).all()
    movable = [r.id for r in rows if (r.tool_id, r.relative_path) not in have]
    kept = [r.id for r in rows if (r.tool_id, r.relative_path) in have]
    for i in range(0, len(movable), _BATCH):
        await db.execute(update(model).where(model.id.in_(movable[i:i + _BATCH])).values(machine_id=target))
    return [str(i) for i in movable], [str(i) for i in kept]


async def merge_duplicate_machines(db: AsyncSession) -> list[dict]:
    """Merge duplicate device records; returns what was merged."""
    # A one-off bulk re-point can outlast the per-statement limit meant for user requests.
    await db.execute(text("SET LOCAL statement_timeout = '15min'"))
    await db.execute(text("SELECT pg_advisory_xact_lock(:k)"), {"k": _LOCK_KEY})
    machines = (await db.execute(select(Machine))).scalars().all()
    done = []
    for keep, fold in plan_merges(list(machines)):
        for old in fold:
            t0 = time.monotonic()
            moved_docs, kept_docs = await _move(db, Document, old.id, keep.id)
            t1 = time.monotonic()
            moved_sync, kept_sync = await _move(db, SyncState, old.id, keep.id)
            log.info("merging %s into %s: documents %.1fs, sync state %.1fs", old.id, keep.id, t1 - t0, time.monotonic() - t1)
            task_ids = (await db.execute(select(DeviceTask.id).where(DeviceTask.machine_id == old.id))).scalars().all()
            if task_ids:
                await db.execute(update(DeviceTask).where(DeviceTask.id.in_(task_ids)).values(machine_id=keep.id))
            moved = {"documents": moved_docs, "sync_state": moved_sync, "device_tasks": [str(i) for i in task_ids]}
            kept = {"documents": kept_docs, "sync_state": kept_sync}
            db.add(MachineMerge(
                from_machine_id=old.id,
                into_machine_id=keep.id,
                name=old.name,
                collector_token_hash=old.collector_token_hash,
                moved=moved,
                kept=kept,
            ))
            old.merged_into = keep.id
            done.append({
                "from": str(old.id),
                "into": str(keep.id),
                "name": old.name,
                "moved_counts": {k: len(v) for k, v in moved.items()},
                "kept_counts": {k: len(v) for k, v in kept.items()},
            })
    await db.commit()
    return done


async def resolve_merged(db: AsyncSession, machine: Machine | None) -> Machine | None:
    """The record a (possibly merged) machine now lives in."""
    seen = 0
    while machine is not None and machine.merged_into is not None and seen < 5:
        machine = await db.get(Machine, machine.merged_into)
        seen += 1
    return machine
