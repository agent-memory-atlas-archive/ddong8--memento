import { app, BrowserWindow, dialog, ipcMain, Menu, nativeImage, nativeTheme, shell, Tray } from "electron";
import { autoUpdater } from "electron-updater";
import { join, sep } from "node:path";

import { loadConfig, saveConfig, type CollectorConfig } from "@memento/daemon";

import { DaemonHost, type DaemonMode } from "./daemon-host";

const UPDATE_CHECK_MS = 6 * 60 * 60_000;
const HIDDEN_ARG = "--hidden";

let win: BrowserWindow | undefined;
let tray: Tray | undefined;
let quitting = false;
let config: CollectorConfig;
const daemon = new DaemonHost();

/** Where the web app is: the server's origin, or a separate web URL on self-hosted setups. */
const serverOrigin = () => new URL(config.webUrl || config.serverUrl).origin;

function modeLabel(mode: DaemonMode): string {
  switch (mode) {
    case "running":
      return "采集运行中";
    case "external":
      return "采集运行中（独立守护进程）";
    case "flutter":
      return "采集由旧版 Memento 负责";
    case "starting":
      return "采集启动中…";
    case "no-token":
      return "登录后开始采集";
    case "crashed":
      return "采集异常，正在重启";
    default:
      return "采集已停止";
  }
}

/**
 * Signs the window in with the device's collector token when it has one and
 * the web session is missing (token-exchange -> /auth/handoff).
 */
async function handoffUrl(next: string): Promise<string | undefined> {
  if (!config.token) return undefined;
  try {
    const res = await fetch(`${config.serverUrl}/api/auth/token-exchange`, {
      method: "POST",
      headers: { "X-Collector-Token": config.token },
      signal: AbortSignal.timeout(15_000),
    });
    if (!res.ok) return undefined;
    const { access_token } = (await res.json()) as { access_token?: string };
    return access_token ? `${serverOrigin()}/auth/handoff#token=${encodeURIComponent(access_token)}&next=${encodeURIComponent(next)}` : undefined;
  } catch {
    return undefined;
  }
}

/** The web session's JWT, once the user has signed in in the window. */
async function webToken(): Promise<string | null> {
  if (!win || win.isDestroyed()) return null;
  if (!win.webContents.getURL().startsWith(serverOrigin())) return null;
  try {
    return (await win.webContents.executeJavaScript('localStorage.getItem("dr_token")', true)) as string | null;
  } catch {
    return null;
  }
}

/** After a sign-in in the window, give the daemon the user's collector token. */
async function adoptWebLogin(): Promise<void> {
  if (config.token) return;
  const jwt = await webToken();
  if (!jwt) return;
  try {
    const res = await fetch(`${config.serverUrl}/api/auth/me`, {
      headers: { Authorization: `Bearer ${jwt}` },
      signal: AbortSignal.timeout(15_000),
    });
    if (!res.ok) return;
    const me = (await res.json()) as { collector_token?: string };
    if (!me.collector_token) return;
    config = { ...config, token: me.collector_token };
    await saveConfig(config);
    await daemon.start();
  } catch {
    // try again on the next navigation
  }
}

async function loadApp(target = "/ask"): Promise<void> {
  if (!win) return;
  const url = (await handoffUrl(target)) ?? `${serverOrigin()}${target}`;
  try {
    await win.loadURL(url);
  } catch {
    await win.loadFile(join(__dirname, "static", "offline.html"), { query: { server: serverOrigin() } });
  }
}

function createWindow(show: boolean): void {
  win = new BrowserWindow({
    width: 1280,
    height: 860,
    minWidth: 380,
    minHeight: 520,
    show,
    title: "Memento",
    // Matches the page while it loads, so there's no dark flash in light mode.
    backgroundColor: nativeTheme.shouldUseDarkColors ? "#0b0b12" : "#f6f5fb",
    titleBarStyle: process.platform === "darwin" ? "hiddenInset" : "default",
    // Windows / Linux: the default File-Edit-View menu adds nothing to the web UI and its
    // bottom edge shows as a dark line under it. Hidden, it still answers Alt and its shortcuts.
    autoHideMenuBar: true,
    webPreferences: {
      preload: join(__dirname, "preload.cjs"),
      contextIsolation: true,
      sandbox: true,
      nodeIntegration: false,
    },
  });

  // Links to other sites open in the browser; GitHub sign-in stays in the window.
  win.webContents.setWindowOpenHandler(({ url }) => {
    void shell.openExternal(url);
    return { action: "deny" };
  });
  win.webContents.on("will-navigate", (event, url) => {
    const { origin, hostname } = new URL(url);
    if (origin === serverOrigin() || hostname === "github.com" || url.startsWith("file:")) return;
    event.preventDefault();
    void shell.openExternal(url);
  });
  win.webContents.on("did-navigate-in-page", () => void adoptWebLogin());
  win.webContents.on("did-finish-load", () => void adoptWebLogin());
  win.webContents.on("did-fail-load", (_e, code, _desc, url, isMainFrame) => {
    if (isMainFrame && code !== -3 && url.startsWith(serverOrigin())) {
      void win?.loadFile(join(__dirname, "static", "offline.html"), { query: { server: serverOrigin() } });
    }
  });

  win.on("close", (event) => {
    // Closing the window keeps Memento in the tray; quit from the tray menu.
    if (!quitting) {
      event.preventDefault();
      win?.hide();
    }
  });

  void loadApp();
}

function showWindow(path?: string): void {
  if (!win || win.isDestroyed()) createWindow(true);
  else {
    win.show();
    win.focus();
  }
  if (path) void loadApp(path);
}

function refreshTray(): void {
  if (!tray) return;
  const openAtLogin = app.getLoginItemSettings().openAtLogin;
  tray.setToolTip(`Memento · ${modeLabel(daemon.mode)}`);
  tray.setContextMenu(
    Menu.buildFromTemplate([
      { label: "打开 Memento", click: () => showWindow() },
      { label: modeLabel(daemon.mode), enabled: false },
      { type: "separator" },
      { label: "本机采集", click: () => showWindow("/collector") },
      {
        label: "立即同步画像和技能",
        enabled: daemon.mode === "running" || daemon.mode === "external",
        click: () => void daemon.call("POST", "/sync-profile").catch(() => {}),
      },
      { type: "separator" },
      {
        label: "开机自动启动",
        type: "checkbox",
        checked: openAtLogin,
        click: (item) => {
          app.setLoginItemSettings({ openAtLogin: item.checked, args: [HIDDEN_ARG] });
          refreshTray();
        },
      },
      { label: "检查更新", enabled: app.isPackaged, click: () => void checkForUpdates(true) },
      { type: "separator" },
      {
        label: "退出 Memento",
        click: () => {
          quitting = true;
          app.quit();
        },
      },
    ]),
  );
}

function createTray(): void {
  const icon = nativeImage.createFromPath(join(__dirname, "static", "tray.png"));
  tray = new Tray(icon.isEmpty() ? nativeImage.createEmpty() : icon);
  tray.on("click", () => showWindow());
  refreshTray();
}

async function checkForUpdates(manual: boolean): Promise<void> {
  if (!app.isPackaged) return;
  try {
    const result = await autoUpdater.checkForUpdates();
    if (manual && !result?.isUpdateAvailable) {
      void dialog.showMessageBox({ message: "已是最新版本", detail: `Memento ${app.getVersion()}` });
    }
  } catch (e) {
    if (manual) void dialog.showMessageBox({ type: "warning", message: "检查更新失败", detail: e instanceof Error ? e.message : String(e) });
  }
}

function setupUpdater(): void {
  autoUpdater.autoDownload = true;
  autoUpdater.autoInstallOnAppQuit = true;
  autoUpdater.on("update-downloaded", async (info) => {
    const { response } = await dialog.showMessageBox({
      type: "info",
      buttons: ["现在重启", "稍后"],
      defaultId: 0,
      message: `Memento ${info.version} 已下载`,
      detail: "重启后生效；也可以稍后退出时自动安装。",
    });
    if (response === 0) {
      quitting = true;
      autoUpdater.quitAndInstall();
    }
  });
  void checkForUpdates(false);
  setInterval(() => void checkForUpdates(false), UPDATE_CHECK_MS);
}

function setupIpc(): void {
  ipcMain.handle("daemon:status", async () => {
    const base = { mode: daemon.mode, label: modeLabel(daemon.mode) };
    try {
      return { ...base, status: await daemon.call("GET", "/status") };
    } catch {
      return { ...base, status: null };
    }
  });
  ipcMain.handle("daemon:logs", async () => {
    try {
      return ((await daemon.call("GET", "/logs")) as { logs: string[] }).logs;
    } catch {
      return [...daemon.recentLogs];
    }
  });
  ipcMain.handle("daemon:action", async (_e, action: unknown) => {
    const paths: Record<string, string> = { resync: "/resync", rediscover: "/rediscover", "sync-profile": "/sync-profile" };
    const path = typeof action === "string" ? paths[action] : undefined;
    if (!path) throw new Error("unknown action");
    return daemon.call("POST", path);
  });
  ipcMain.handle("app:info", () => ({
    version: app.getVersion(),
    platform: process.platform,
    openAtLogin: app.getLoginItemSettings().openAtLogin,
    packaged: app.isPackaged,
    // How AI tools start the bundled MCP server: this app's binary as Node.
    mcp: {
      command: process.execPath,
      args: [join(__dirname, "mcp.mjs").replace(`app.asar${sep}`, `app.asar.unpacked${sep}`)],
      env: { ELECTRON_RUN_AS_NODE: "1" },
    },
  }));
  ipcMain.handle("app:set-open-at-login", (_e, on: unknown) => {
    app.setLoginItemSettings({ openAtLogin: on === true, args: [HIDDEN_ARG] });
    refreshTray();
    return app.getLoginItemSettings().openAtLogin;
  });
  ipcMain.handle("app:check-updates", () => checkForUpdates(true));

  const forward = (channel: string) => (payload: unknown) => {
    if (win && !win.isDestroyed()) win.webContents.send(channel, payload);
  };
  daemon.on("status", forward("daemon:status-event"));
  daemon.on("log", forward("daemon:log-event"));
  daemon.on("mode", (mode: DaemonMode) => {
    refreshTray();
    forward("daemon:mode-event")({ mode, label: modeLabel(mode) });
  });
}

if (!app.requestSingleInstanceLock()) {
  app.quit();
} else {
  app.on("second-instance", () => showWindow());
  app.on("before-quit", () => {
    quitting = true;
  });
  app.on("will-quit", (event) => {
    if (daemon.mode === "running" || daemon.mode === "starting") {
      event.preventDefault();
      void daemon.stop().finally(() => app.exit(0));
    }
  });
  app.on("activate", () => showWindow());

  void app.whenReady().then(async () => {
    config = await loadConfig();
    setupIpc();
    createTray();
    const hidden = process.argv.includes(HIDDEN_ARG) || app.getLoginItemSettings().wasOpenedAtLogin;
    createWindow(!hidden);
    if (config.token) await daemon.start();
    else daemon.mode = "no-token";
    refreshTray();
    setupUpdater();
  });
}
