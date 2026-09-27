"""System health overview for the client's health page."""

from __future__ import annotations

from fastapi import APIRouter, Depends
from sqlalchemy.ext.asyncio import AsyncSession

from ..db.models import User
from ..db.session import get_db
from ..middleware.auth import get_current_user
from ..services.health_service import build_overview

router = APIRouter(prefix="/api/health", tags=["health"])


@router.get("/overview")
async def overview(
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
) -> dict:
    return await build_overview(db, user)
