"use client";

import { useEffect, useState } from "react";
import { api } from "@/lib/api-client";
import { useI18n } from "@/lib/i18n";
import { Btn, Glass } from "@/components/aurora/primitives";

type Settings = Record<string, unknown>;

/** Push notifications: Memento native mobile app and optional fallback (Bark / ntfy). */
export default function NotifySettings() {
  const { t } = useI18n();
  const n = t.notify;
  const [settings, setSettings] = useState<Settings | null>(null);
  const [url, setUrl] = useState("");
  const [busy, setBusy] = useState(false);
  const [showFallback, setShowFallback] = useState(false);
  const [message, setMessage] = useState<{ text: string; error: boolean } | null>(null);

  useEffect(() => {
    api
      .getNotifySettings()
      .then(setSettings)
      .catch((e: Error) => setMessage({ text: e.message, error: true }));
  }, []);

  const run = async (action: () => Promise<void>) => {
    setBusy(true);
    setMessage(null);
    try {
      await action();
    } catch (e) {
      setMessage({ text: (e as Error).message, error: true });
    } finally {
      setBusy(false);
    }
  };

  const save = (value: string) =>
    run(async () => {
      setSettings(await api.updateNotifySettings({ bark_url: value }));
      setUrl("");
      setMessage({ text: value ? n.saved : n.cleared, error: false });
    });

  const toggle = (key: string, value: boolean) =>
    run(async () => {
      setSettings(await api.updateNotifySettings({ [key]: value }));
    });

  const test = () =>
    run(async () => {
      await api.sendTestNotification();
      setMessage({ text: n.testSent, error: false });
    });

  const barkConfigured = settings?.bark_configured === true;
  const nativeConfigured = settings?.native_configured === true;
  const deviceCount = Number(settings?.device_tokens_count ?? 0);
  const canTest = nativeConfigured || barkConfigured;

  const switches: { key: string; title: string; hint: string }[] = [
    { key: "notify_risky", title: n.risky, hint: n.riskyHint },
    { key: "notify_task_done", title: n.taskDone, hint: n.taskDoneHint },
    { key: "notify_health", title: n.health, hint: n.healthHint },
    { key: "notify_learning", title: n.learning, hint: n.learningHint },
    { key: "notify_todo", title: n.todo, hint: n.todoHint },
  ];

  return (
    <Glass padding={22} radius={20} style={{ marginBottom: 20 }}>
      {/* 1. Memento Native Mobile App Channel */}
      <div className="mb-4 p-3.5 rounded-xl bg-[var(--aurora-chip)] border border-[var(--aurora-border)] leading-relaxed">
        <div className="flex items-center justify-between gap-2 mb-1.5">
          <span className="text-sm font-semibold text-[var(--aurora-fg1)] flex items-center gap-1.5">
            📱 {n.nativeTitle}
          </span>
          <span
            className={`text-xs px-2 py-0.5 rounded-full font-medium ${
              nativeConfigured
                ? "bg-emerald-500/15 text-emerald-400 border border-emerald-500/30"
                : "bg-[var(--aurora-border)] text-[var(--aurora-fg3)]"
            }`}
          >
            {nativeConfigured ? `已激活（${deviceCount} 台设备）` : "未连接"}
          </span>
        </div>
        <p className="text-xs text-[var(--aurora-fg3)] m-0">
          {nativeConfigured
            ? "Memento 移动端（iOS / Android）已自动注册系统原生推送，危险操作、任务完成与 AI 建议将直接以 Memento 名义弹出锁屏通知与响铃，无需安装 Bark 等任何第三方 App。"
            : "Memento 移动端自带系统级原生通知！只需在手机端打开并登录 Memento，即可自动注册原生推送通道，无需下载任何第三方应用。"}
        </p>
      </div>

      {/* Test notification button */}
      <div className="flex items-center gap-3 mb-4">
        <Btn variant="glass" size="sm" disabled={busy || !canTest} onClick={test}>
          {n.test}
        </Btn>
        <button
          type="button"
          onClick={() => setShowFallback((prev) => !prev)}
          className="text-xs text-[var(--aurora-accent)] hover:underline bg-transparent border-0 cursor-pointer p-0"
        >
          {showFallback ? "收起备用外部通道 (Bark/ntfy)" : "配置备用外部通道 (Bark/ntfy)..."}
        </button>
      </div>

      {/* 2. Optional Fallback Channel (Bark / ntfy) */}
      {(showFallback || barkConfigured) && (
        <div className="mb-4 p-3 rounded-xl border border-[var(--aurora-border-strong)] bg-[var(--aurora-surface-solid)]/40">
          <div className="text-xs font-semibold text-[var(--aurora-fg2)] mb-1.5 flex items-center gap-1">
            🔔 {n.fallbackTitle}
          </div>
          <div className="text-xs text-[var(--aurora-fg3)] mb-2 space-y-0.5">
            <div>如未安装 Memento 移动客户端，可选填 Bark (iOS) 或 ntfy (Android) 作为备用推送地址：</div>
          </div>
          {settings && (
            <p style={{ fontSize: 12, margin: "0 0 6px", color: barkConfigured ? "#10B981" : "var(--aurora-fg3)" }}>
              {barkConfigured ? `${n.current}${String(settings.bark_masked ?? "")}` : n.notSet}
            </p>
          )}
          <input
            value={url}
            onChange={(e) => setUrl(e.target.value)}
            placeholder={barkConfigured ? n.replaceHint : "iOS 填 https://api.day.app/…  或 Android 填 https://ntfy.sh/…"}
            autoCorrect="off"
            style={{
              width: "100%",
              fontSize: 13,
              padding: "7px 10px",
              borderRadius: 8,
              border: "1px solid var(--aurora-border-strong)",
              background: "var(--aurora-surface-solid)",
              color: "var(--aurora-fg1)",
            }}
          />
          <div style={{ display: "flex", gap: 8, marginTop: 8, flexWrap: "wrap" }}>
            <Btn size="sm" disabled={busy || !url.trim()} onClick={() => save(url.trim())}>
              {n.save}
            </Btn>
            {barkConfigured && (
              <Btn variant="ghost" size="sm" disabled={busy} onClick={() => save("")}>
                {n.clear}
              </Btn>
            )}
          </div>
        </div>
      )}

      {/* Notification Category Switches */}
      <div className="border-t border-[var(--aurora-border)] pt-2 mt-2">
        {settings &&
          switches.map((s) => (
            <label key={s.key} style={{ display: "flex", gap: 12, alignItems: "flex-start", padding: "10px 0 0", cursor: "pointer" }}>
              <input
                type="checkbox"
                checked={settings[s.key] !== false}
                disabled={busy}
                onChange={(e) => toggle(s.key, e.target.checked)}
                style={{ marginTop: 3, width: 15, height: 15, accentColor: "var(--aurora-accent)" }}
              />
              <span>
                <span style={{ display: "block", fontSize: 13.5, color: "var(--aurora-fg1)" }}>{s.title}</span>
                <span style={{ display: "block", fontSize: 12, color: "var(--aurora-fg3)", marginTop: 2 }}>{s.hint}</span>
              </span>
            </label>
          ))}
      </div>

      {message && <p style={{ margin: "12px 0 0", fontSize: 12.5, color: message.error ? "#DC2626" : "var(--aurora-fg2)" }}>{message.text}</p>}
    </Glass>
  );
}
