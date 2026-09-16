"""Device WebSocket Connection Manager.

Maintains persistent WebSocket connections to online collector devices,
enabling sub-second task dispatch, live chunked stdout/stderr streaming,
and real-time process cancellation.
"""

from __future__ import annotations

import asyncio
import logging
from typing import Any

from fastapi import WebSocket

logger = logging.getLogger("server.ws_manager")


class DeviceConnectionManager:
    def __init__(self) -> None:
        # device_id (collector_token_hash) -> WebSocket
        self._connections: dict[str, WebSocket] = {}
        # task_id (str) -> asyncio.Queue
        self._task_queues: dict[str, asyncio.Queue] = {}
        # task_id (str) -> WebSocket (exact active connection running this task)
        self._task_connections: dict[str, WebSocket] = {}

    def register(self, device_id: str, ws: WebSocket) -> None:
        self._connections[device_id] = ws
        logger.info("Device connected via WebSocket: %s", device_id)

    def unregister(self, device_id: str, ws: WebSocket | None = None) -> None:
        target_ws = ws or self._connections.get(device_id)
        if target_ws:
            keys_to_remove = [k for k, v in self._connections.items() if v is target_ws]
            for k in keys_to_remove:
                self._connections.pop(k, None)
            task_keys_to_remove = [k for k, v in self._task_connections.items() if v is target_ws]
            for k in task_keys_to_remove:
                self._task_connections.pop(k, None)
        else:
            self._connections.pop(device_id, None)
        logger.info("Device disconnected from WebSocket: %s", device_id)

    def has_device(self, device_id: str) -> bool:
        return device_id in self._connections

    async def send_task(self, device_id: str, task: dict[str, Any]) -> bool:
        """Send a task directly to the device over WebSocket."""
        ws = self._connections.get(device_id)
        if not ws:
            return False
        try:
            await ws.send_json({
                "type": "task_dispatch",
                "task": task,
            })
            tid = str(task.get("id") or "")
            if tid:
                self._task_connections[tid] = ws
            logger.info("Dispatched task %s to %s via WebSocket", tid, device_id)
            return True
        except Exception as e:
            logger.warning("Failed to dispatch task to %s via WebSocket: %s", device_id, e)
            self.unregister(device_id, ws)
            return False

    async def send_cancel(self, device_id: str, task_id: str) -> bool:
        """Send cancellation frame to the device to kill the running subprocess."""
        tid = str(task_id)
        ws = self._task_connections.get(tid) or self._connections.get(device_id)
        if not ws:
            logger.warning("Cannot cancel task %s: no WebSocket connection found for device %s or task", tid, device_id)
            return False
        try:
            await ws.send_json({
                "type": "task_cancel",
                "task_id": tid,
            })
            logger.info("Sent task_cancel for %s to device via WebSocket", tid)
            return True
        except Exception as e:
            logger.warning("Failed to send cancel for %s via WebSocket: %s", tid, e)
            return False

    async def send_input(self, device_id: str, task_id: str, input_text: str) -> bool:
        """Send input frame to the device to forward stdin into the running subprocess."""
        tid = str(task_id)
        ws = self._task_connections.get(tid) or self._connections.get(device_id)
        if not ws:
            logger.warning("Cannot forward input to task %s: no WebSocket connection found for device %s or task", tid, device_id)
            return False
        try:
            await ws.send_json({
                "type": "task_input",
                "task_id": tid,
                "input": str(input_text),
            })
            logger.info("Sent task_input for %s via WebSocket: %s", tid, input_text)
            return True
        except Exception as e:
            logger.warning("Failed to send input for %s via WebSocket: %s", tid, e)
            return False

    def subscribe_task(self, task_id: str) -> asyncio.Queue:
        """Create a dedicated event queue for a running task's streaming output."""
        q: asyncio.Queue = asyncio.Queue(maxsize=1000)
        self._task_queues[task_id] = q
        return q

    def unsubscribe_task(self, task_id: str) -> None:
        self._task_queues.pop(task_id, None)
        self._task_connections.pop(task_id, None)

    def push_chunk(self, task_id: str, stream: str, text: str) -> None:
        q = self._task_queues.get(task_id)
        if q:
            try:
                q.put_nowait({
                    "type": "task_chunk",
                    "task_id": task_id,
                    "stream": stream,
                    "text": text,
                })
            except asyncio.QueueFull:
                logger.warning("Task stream queue full for %s, dropping chunk", task_id)

    def push_progress(self, task_id: str, status: str) -> None:
        q = self._task_queues.get(task_id)
        if q:
            try:
                q.put_nowait({
                    "type": "task_progress",
                    "task_id": task_id,
                    "status": status,
                })
            except asyncio.QueueFull:
                pass

    def push_finished(self, task_id: str, result: dict[str, Any]) -> None:
        self._task_connections.pop(task_id, None)
        q = self._task_queues.get(task_id)
        if q:
            try:
                q.put_nowait({
                    "type": "task_finished",
                    "task_id": task_id,
                    "result": result,
                })
            except asyncio.QueueFull:
                pass


ws_manager = DeviceConnectionManager()
