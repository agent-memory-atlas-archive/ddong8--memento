import createClient, { type Client } from "openapi-fetch";

import type { paths } from "./api.gen.js";
import type { FetchLike } from "./ask-stream.js";

export type MementoApi = Client<paths>;

export interface ClientOptions {
  baseUrl: string;
  /** Read on every request, so a refreshed or cleared token takes effect at once. */
  getToken?: () => string | null | undefined | Promise<string | null | undefined>;
  fetch?: FetchLike;
}

/**
 * A typed client for the Memento server, generated from its OpenAPI schema
 * (`npm run gen:api`). Paths, parameters and request bodies are checked at
 * compile time; endpoints that return plain dicts come back as unknown JSON.
 */
export function createMementoClient(options: ClientOptions): MementoApi {
  const client = createClient<paths>({
    baseUrl: options.baseUrl.replace(/\/+$/, ""),
    fetch: options.fetch ? (request: Request) => options.fetch!(request.url, request) : undefined,
  });
  if (options.getToken) {
    client.use({
      async onRequest({ request }) {
        const token = await options.getToken!();
        if (token) request.headers.set("Authorization", `Bearer ${token}`);
        return request;
      },
    });
  }
  return client;
}

/** A readable message for a failed API call, for showing to the user. */
export function describeApiError(status: number | undefined, body: unknown): string {
  const detail = body && typeof body === "object" && "detail" in body ? (body as { detail: unknown }).detail : undefined;
  if (typeof detail === "string" && detail) return detail;
  if (status === undefined) return "连不上服务端，检查网络后再试";
  if (status === 401) return "登录已过期，请重新登录";
  if (status >= 500) return `服务端出错（${status}），稍后再试`;
  return `请求失败（${status}）`;
}
