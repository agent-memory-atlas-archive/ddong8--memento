import * as SecureStore from "expo-secure-store";
import { createContext, useCallback, useContext, useEffect, useMemo, useState, type ReactNode } from "react";

import { ApiError } from "./api";

export const DEFAULT_SERVER = "https://mem.ihasy.com";
const SERVER_KEY = "memento.server";
const TOKEN_KEY = "memento.token";

interface Session {
  ready: boolean;
  server: string;
  token: string | null;
  signIn(server: string, email: string, password: string): Promise<void>;
  signInWithToken(server: string, token: string): Promise<void>;
  signOut(): Promise<void>;
}

const SessionContext = createContext<Session | null>(null);

/** The signed-in user's server and JWT, kept in the device keychain. */
export function SessionProvider({ children }: { children: ReactNode }) {
  const [ready, setReady] = useState(false);
  const [server, setServer] = useState(DEFAULT_SERVER);
  const [token, setToken] = useState<string | null>(null);

  useEffect(() => {
    void (async () => {
      const [s, t] = await Promise.all([SecureStore.getItemAsync(SERVER_KEY), SecureStore.getItemAsync(TOKEN_KEY)]);
      const base = s || DEFAULT_SERVER;
      if (s) setServer(s);
      // Tokens last a day: trade the stored one for a fresh one on each start.
      if (t) {
        try {
          const res = await fetch(`${base}/api/auth/refresh`, { method: "POST", headers: { Authorization: `Bearer ${t}` } });
          if (res.ok) {
            const { access_token } = (await res.json()) as { access_token: string };
            await SecureStore.setItemAsync(TOKEN_KEY, access_token);
            setToken(access_token);
          } else if (res.status === 401) {
            await SecureStore.deleteItemAsync(TOKEN_KEY);
          } else {
            setToken(t);
          }
        } catch {
          setToken(t); // offline: keep it, calls will fail visibly
        }
      }
      setReady(true);
    })();
  }, []);

  const signOut = useCallback(async () => {
    await SecureStore.deleteItemAsync(TOKEN_KEY);
    setToken(null);
  }, []);

  const signIn = useCallback(async (serverUrl: string, email: string, password: string) => {
    const base = (serverUrl.trim() || DEFAULT_SERVER).replace(/\/+$/, "");
    const res = await fetch(`${base}/api/auth/login`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ email: email.trim(), password }),
    });
    if (!res.ok) {
      const data = (await res.json().catch(() => ({}))) as { detail?: string };
      throw new ApiError(res.status === 401 ? "邮箱或密码不对" : data.detail || `登录失败（${res.status}）`, res.status);
    }
    const { access_token } = (await res.json()) as { access_token: string };
    await Promise.all([SecureStore.setItemAsync(SERVER_KEY, base), SecureStore.setItemAsync(TOKEN_KEY, access_token)]);
    setServer(base);
    setToken(access_token);
  }, []);

  const signInWithToken = useCallback(async (serverUrl: string, accessToken: string) => {
    const base = (serverUrl.trim() || DEFAULT_SERVER).replace(/\/+$/, "");
    await Promise.all([SecureStore.setItemAsync(SERVER_KEY, base), SecureStore.setItemAsync(TOKEN_KEY, accessToken)]);
    setServer(base);
    setToken(accessToken);
  }, []);

  const value = useMemo(() => ({ ready, server, token, signIn, signInWithToken, signOut }), [ready, server, token, signIn, signInWithToken, signOut]);
  return <SessionContext.Provider value={value}>{children}</SessionContext.Provider>;
}

export function useSession(): Session {
  const s = useContext(SessionContext);
  if (!s) throw new Error("useSession outside SessionProvider");
  return s;
}
