import asyncio
import pytest
from server.api.ask import sse_keepalive_generator


@pytest.mark.asyncio
async def test_sse_keepalive_normal_flow():
    async def normal_gen():
        yield "data: 1\n\n"
        yield "data: 2\n\n"

    items = []
    async for item in sse_keepalive_generator(normal_gen(), interval=0.1):
        items.append(item)

    assert items == ["data: 1\n\n", "data: 2\n\n"]


@pytest.mark.asyncio
async def test_sse_keepalive_idle_yields_ping():
    async def slow_gen():
        yield "data: start\n\n"
        await asyncio.sleep(0.25)
        yield "data: finish\n\n"

    items = []
    async for item in sse_keepalive_generator(slow_gen(), interval=0.08):
        items.append(item)

    assert "data: start\n\n" in items
    assert ": keepalive\n\n" in items
    assert "data: finish\n\n" in items
    assert items.index("data: start\n\n") < items.index(": keepalive\n\n") < items.index("data: finish\n\n")


@pytest.mark.asyncio
async def test_sse_keepalive_exception_propagation():
    async def failing_gen():
        yield "data: ok\n\n"
        raise ValueError("stream boom")

    items = []
    with pytest.raises(ValueError, match="stream boom"):
        async for item in sse_keepalive_generator(failing_gen(), interval=0.1):
            items.append(item)

    assert items == ["data: ok\n\n"]
