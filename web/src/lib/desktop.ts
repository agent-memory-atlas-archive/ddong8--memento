/** What the Memento desktop app exposes to the web UI (apps/desktop/src/preload.ts). */
export interface DaemonStatus {
  running: boolean;
  online: boolean;
  deviceName: string;
  deviceId: string;
  serverUrl: string;
  tools: Record<string, { root?: string; projects?: { name: string; path: string }[] } & Record<string, unknown>>;
  runningTasks: string[];
  startedAt: string | null;
}

export interface DaemonState {
  mode: "starting" | "running" | "external" | "flutter" | "stopped" | "no-token" | "crashed";
  label: string;
  status: DaemonStatus | null;
}

export interface MementoDesktop {
  isDesktop: true;
  info(): Promise<{ version: string; platform: string; openAtLogin: boolean; packaged: boolean }>;
  setOpenAtLogin(on: boolean): Promise<boolean>;
  checkForUpdates(): Promise<void>;
  daemon: {
    status(): Promise<DaemonState>;
    logs(): Promise<string[]>;
    action(name: "resync" | "rediscover" | "sync-profile"): Promise<unknown>;
    onStatus(cb: (s: DaemonStatus) => void): () => void;
    onLog(cb: (line: string) => void): () => void;
    onMode(cb: (m: { mode: DaemonState["mode"]; label: string }) => void): () => void;
  };
}

/** The desktop bridge, or null in a plain browser. */
export function desktop(): MementoDesktop | null {
  if (typeof window === "undefined") return null;
  const d = (window as unknown as { mementoDesktop?: MementoDesktop }).mementoDesktop;
  return d?.isDesktop ? d : null;
}
