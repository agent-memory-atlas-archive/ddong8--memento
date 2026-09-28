import { mergeTaskEvent, type AskSource, type AskStreamEvent, type TaskResult } from "@memento/core";

import type { ToolCall } from "../components/TaskCard";

export interface Turn {
  role: "user" | "assistant";
  content: string;
  thinking?: string;
  sources?: AskSource[];
  toolCalls?: ToolCall[];
  error?: boolean;
}

const FINISHED = new Set(["succeeded", "failed", "timeout", "cancelled"]);

/** The tool call a device event belongs to: by task id, then call id, then the open device call. */
function findCall(calls: ToolCall[], taskId?: string, callId?: string, deviceName?: string): number {
  let i = taskId ? calls.findIndex((c) => c.result?.task_id === taskId) : -1;
  if (i < 0 && callId) i = calls.findIndex((c) => c.id === callId);
  if (i < 0 && deviceName) i = calls.findIndex((c) => (c.device_name === deviceName || c.result?.device_name === deviceName) && !FINISHED.has(c.result?.status ?? ""));
  if (i < 0) {
    for (let j = calls.length - 1; j >= 0; j--) {
      if (calls[j]!.name === "run_on_device" && !FINISHED.has(calls[j]!.result?.status ?? "")) return j;
    }
  }
  return i;
}

/** Applies one stream event to the assistant turn being written. */
export function applyEvent(turn: Turn, evt: AskStreamEvent): Turn {
  const calls = [...(turn.toolCalls ?? [])];
  const patch = (i: number, result: TaskResult) => {
    if (i >= 0) calls[i] = { ...calls[i]!, result };
    return { ...turn, toolCalls: calls };
  };
  switch (evt.type) {
    case "sources":
      return { ...turn, sources: evt.sources };
    case "thinking":
      return { ...turn, thinking: (turn.thinking ?? "") + evt.text };
    case "delta":
      return { ...turn, content: turn.content + evt.text };
    case "error":
      return { ...turn, content: evt.message || "出错了", error: true };
    case "tool_call": {
      const id = evt.id ?? evt.tool_call_id ?? `call_${calls.length}`;
      if (!calls.some((c) => c.id === id)) calls.push({ id, name: evt.name, args: evt.args ?? {}, device_name: evt.device_name });
      return { ...turn, toolCalls: calls };
    }
    case "task_progress": {
      const i = findCall(calls, evt.task_id, evt.tool_call_id, evt.device_name);
      if (i < 0) return turn;
      const prev = calls[i]!.result ?? {};
      return patch(i, { ...prev, task_id: evt.task_id ?? prev.task_id, device_name: evt.device_name ?? prev.device_name, status: evt.status ?? prev.status });
    }
    case "task_chunk": {
      const i = findCall(calls, evt.task_id, evt.tool_call_id, evt.device_name);
      if (i < 0) return turn;
      const prev = calls[i]!.result ?? {};
      const key = evt.stream === "stderr" ? "stderr" : "stdout";
      return patch(i, { ...prev, task_id: evt.task_id ?? prev.task_id, status: "running", [key]: (prev[key] ?? "") + evt.text });
    }
    case "task_event": {
      const i = findCall(calls, evt.task_id, evt.tool_call_id);
      if (i < 0) return turn;
      const prev = calls[i]!.result ?? {};
      return patch(i, { ...prev, task_id: prev.task_id ?? evt.task_id, events: mergeTaskEvent(prev.events ?? [], evt.event) });
    }
    case "tool_result": {
      const i = findCall(calls, evt.result?.task_id ?? evt.task_id, evt.tool_call_id, evt.result?.device_name);
      const idx = i >= 0 ? i : calls.length - 1;
      if (idx < 0) return turn;
      const events = evt.result?.events ?? calls[idx]!.result?.events;
      return patch(idx, { ...evt.result, ...(events ? { events } : {}) });
    }
    default:
      return turn;
  }
}
