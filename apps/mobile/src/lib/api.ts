import { str } from "./format";

export type Json = Record<string, unknown>;

export class ApiError extends Error {
  constructor(
    message: string,
    readonly status: number,
  ) {
    super(message);
  }
}

/** Plain-language message for a failed call. */
export function describeError(e: unknown): string {
  if (e instanceof ApiError) {
    if (e.status === 401) return "登录已过期，请重新登录";
    if (e.status === 404) return "服务端版本太旧，没有这个功能";
    if (e.status >= 500) return `服务端出错（${e.status}），稍后再试`;
    return e.message;
  }
  if (e instanceof TypeError) return "连不上服务端，检查网络后再试";
  return e instanceof Error ? e.message : String(e);
}

/** Calls to the Memento server as the signed-in user. */
export function createApi(server: string, token: string | null, onUnauthorized: () => void) {
  const base = server.replace(/\/+$/, "");
  async function request<T>(method: string, path: string, body?: unknown): Promise<T> {
    const res = await fetch(`${base}${path}`, {
      method,
      headers: {
        ...(token ? { Authorization: `Bearer ${token}` } : {}),
        ...(body !== undefined ? { "Content-Type": "application/json" } : {}),
      },
      body: body !== undefined ? JSON.stringify(body) : undefined,
    });
    if (res.status === 401 && token) onUnauthorized();
    if (!res.ok) {
      let detail = "";
      try {
        const data = (await res.json()) as { detail?: unknown };
        detail = typeof data.detail === "string" ? data.detail : "";
      } catch {
        // not JSON
      }
      throw new ApiError(detail || `HTTP ${res.status}`, res.status);
    }
    return (await res.json()) as T;
  }
  const get = <T = Json>(path: string) => request<T>("GET", path);
  const post = <T = Json>(path: string, body?: unknown) => request<T>("POST", path, body ?? {});
  const put = <T = Json>(path: string, body: unknown) => request<T>("PUT", path, body);
  const q = (params: Record<string, unknown>) => {
    const s = Object.entries(params)
      .filter(([, v]) => v !== undefined && v !== null && v !== "")
      .map(([k, v]) => `${encodeURIComponent(k)}=${encodeURIComponent(str(v))}`)
      .join("&");
    return s ? `?${s}` : "";
  };

  return {
    base,
    token,
    me: () => get("/api/auth/me"),
    // ask
    conversations: () => get<Json[]>("/api/ask/conversations"),
    conversation: (id: string) => get(`/api/ask/conversations/${id}`),
    conversationRun: (id: string) => get(`/api/ask/conversations/${id}/run`),
    deleteConversation: (id: string) => request<Json>("DELETE", `/api/ask/conversations/${id}`),
    sendTaskInput: (taskId: string, input: string) => post<{ ok?: boolean }>(`/api/tasks/${taskId}/input`, { input }),
    cancelTask: (taskId: string) => post(`/api/tasks/${taskId}/cancel`),
    // devices
    devices: () => get<Json[]>("/api/devices"),
    // memory
    search: (query: string) => get(`/api/search${q({ q: query, limit: 20 })}`),
    semantic: (query: string) => get(`/api/memory/semantic${q({ q: query, limit: 20 })}`),
    coreMarkdown: () => get("/api/memory/core/markdown"),
    corrections: () => get("/api/learning/corrections"),
    acceptCorrection: (id: string) => post(`/api/learning/corrections/${id}/accept`),
    dismissCorrection: (id: string) => post(`/api/learning/corrections/${id}/dismiss`),
    document: (id: string) => get(`/api/documents/${id}`),
    // daily & todos
    dailyDates: (days = 30) => get<Json[]>(`/api/daily${q({ days })}`),
    daily: (date: string) => get(`/api/daily/${date}${q({ tz_offset: new Date().getTimezoneOffset() })}`),
    todos: () => get("/api/todos"),
    addTodo: (title: string, due?: string) => post("/api/todos", { title, ...(due ? { due } : {}) }),
    updateTodo: (id: string, fields: Json) => put(`/api/todos/${id}`, fields),
    // health & settings
    health: () => get("/api/health/overview"),
    notifySettings: () => get("/api/notify/settings"),
    updateNotifySettings: (fields: Json) => put("/api/notify/settings", fields),
    testNotification: () => post("/api/notify/test"),
  };
}

export type Api = ReturnType<typeof createApi>;
