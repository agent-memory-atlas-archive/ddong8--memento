import { describe, expect, it } from "vitest";

import { AskStream, type AskStreamEvent, type FetchLike } from "../src/index.js";

type Call = { url: string; method: string; body?: string };

/** An SSE body from frames; `hang` keeps the stream open after them (a silent dead connection). */
function sse(frames: string[], hang = false): Response {
  const encoder = new TextEncoder();
  const body = new ReadableStream<Uint8Array>({
    start(controller) {
      for (const f of frames) controller.enqueue(encoder.encode(f));
      if (!hang) controller.close();
    },
  });
  return new Response(body, { status: 200, headers: { "Content-Type": "text/event-stream" } });
}

const frame = (id: number, event: object) => `id: ${id}\ndata: ${JSON.stringify(event)}\n\n`;

function fakeServer(responses: ((call: Call, signal?: AbortSignal) => Response | Promise<Response>)[]) {
  const calls: Call[] = [];
  const fetch: FetchLike = async (url, init) => {
    const call = { url, method: init?.method ?? "GET", body: init?.body as string | undefined };
    calls.push(call);
    const next = responses.shift();
    if (!next) throw new TypeError("no more responses");
    return next(call, init?.signal ?? undefined);
  };
  return { fetch, calls };
}

function run(start: (opts: Parameters<typeof AskStream.ask>[1]) => AskStream, fetch: FetchLike, idleTimeoutMs = 30_000) {
  const events: AskStreamEvent[] = [];
  let gone = false;
  return new Promise<{ events: AskStreamEvent[]; gone: boolean; stream: AskStream }>((resolve) => {
    const stream = start({
      baseUrl: "https://mem.example/",
      token: "tok",
      fetch,
      idleTimeoutMs,
      sleep: async () => {},
      onEvent: (e) => events.push(e),
      onRunGone: () => {
        gone = true;
      },
      onDone: () => resolve({ events, gone, stream }),
    });
  });
}

describe("AskStream", () => {
  it("streams a run to the end", async () => {
    const server = fakeServer([
      () =>
        sse([
          frame(1, { type: "conversation_id", id: "c1", title: "t" }),
          frame(2, { type: "delta", text: "你好" }),
          frame(3, { type: "done" }),
        ]),
    ]);
    const { events, stream } = await run((o) => AskStream.ask({ question: "hi" }, o), server.fetch);
    expect(events.map((e) => e.type)).toEqual(["conversation_id", "delta", "done"]);
    expect(server.calls).toHaveLength(1);
    expect(server.calls[0]!.url).toBe("https://mem.example/api/ask");
    expect(JSON.parse(server.calls[0]!.body!).request_id).toMatch(/^[0-9a-f]{32}$/);
    expect(stream.lastId).toBe(3);
  });

  it("reattaches after a dropped connection without resending", async () => {
    const server = fakeServer([
      () => sse([frame(1, { type: "conversation_id", id: "c1" }), frame(2, { type: "delta", text: "a" })]),
      () => sse([frame(3, { type: "delta", text: "b" }), frame(4, { type: "done" })]),
    ]);
    const { events } = await run((o) => AskStream.ask({ question: "hi" }, o), server.fetch);
    expect(events.filter((e) => e.type === "delta").map((e) => (e as { text: string }).text)).toEqual(["a", "b"]);
    expect(server.calls.map((c) => `${c.method} ${c.url}`)).toEqual([
      "POST https://mem.example/api/ask",
      "GET https://mem.example/api/ask/conversations/c1/stream?after=2",
    ]);
  });

  it("retries a send the server never got, with the same request id", async () => {
    const server = fakeServer([
      () => new Response("busy", { status: 503 }),
      () => sse([frame(1, { type: "conversation_id", id: "c1" }), frame(2, { type: "done" })]),
    ]);
    await run((o) => AskStream.ask({ question: "hi" }, o), server.fetch);
    expect(server.calls).toHaveLength(2);
    expect(JSON.parse(server.calls[0]!.body!).request_id).toBe(JSON.parse(server.calls[1]!.body!).request_id);
  });

  it("reports a conversation that is still busy", async () => {
    const server = fakeServer([() => new Response("", { status: 409 })]);
    const { events } = await run((o) => AskStream.ask({ question: "hi" }, o), server.fetch);
    expect(events).toEqual([{ type: "error", message: "这个对话还有任务在运行，请等它结束或先停止" }]);
  });

  it("tells when the run is no longer on the server", async () => {
    const server = fakeServer([() => new Response("", { status: 404 })]);
    const { gone } = await run((o) => AskStream.attach("c9", 5, o), server.fetch);
    expect(gone).toBe(true);
    expect(server.calls[0]!.url).toContain("/conversations/c9/stream?after=5");
  });

  it("drops a silent connection and resumes from the last event", async () => {
    const server = fakeServer([
      (_c, signal) => {
        const res = sse([frame(1, { type: "conversation_id", id: "c1" })], true);
        signal?.addEventListener("abort", () => res.body?.cancel().catch(() => {}));
        return res;
      },
      () => sse([frame(2, { type: "done" })]),
    ]);
    const { events } = await run((o) => AskStream.ask({ question: "hi" }, o), server.fetch, 50);
    expect(events.map((e) => e.type)).toEqual(["conversation_id", "done"]);
    expect(server.calls[1]!.url).toContain("after=1");
  });
});
