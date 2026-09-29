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

import uuid
from collections import defaultdict
from datetime import datetime, timezone

from sqlalchemy import and_, exists, select, text, update
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import aliased

from ..db.models import DeviceTask, Document, Machine, MachineMerge, SyncState
from .user_filter import normalize_device_name

_LOCK_KEY = 0x6D656D656E746F  # pg advisory lock: only one api instance merges at a time


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


async def _move(db: AsyncSession, model, key_cols: tuple, source: uuid.UUID, target: uuid.UUID) -> tuple[list, list]:
    """Re-point rows of `model` from source to target, except where target already has the same key."""
    other = aliased(model)
    clash = exists().where(
        and_(other.machine_id == target, *[getattr(other, c) == getattr(model, c) for c in key_cols])
    )
    movable = (await db.execute(select(model.id).where(model.machine_id == source, ~clash))).scalars().all()
    kept = (await db.execute(select(model.id).where(model.machine_id == source, clash))).scalars().all()
    if movable:
        await db.execute(update(model).where(model.id.in_(movable)).values(machine_id=target))
    return [str(i) for i in movable], [str(i) for i in kept]


async def merge_duplicate_machines(db: AsyncSession) -> list[dict]:
    """Merge duplicate device records; returns what was merged."""
    await db.execute(text("SELECT pg_advisory_xact_lock(:k)"), {"k": _LOCK_KEY})
    machines = (await db.execute(select(Machine))).scalars().all()
    done = []
    for keep, fold in plan_merges(list(machines)):
        for old in fold:
            moved_docs, kept_docs = await _move(db, Document, ("tool_id", "relative_path"), old.id, keep.id)
            moved_sync, kept_sync = await _move(db, SyncState, ("tool_id", "relative_path"), old.id, keep.id)
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
