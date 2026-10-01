"use client";

import { useEffect, useState } from "react";
import { api } from "@/lib/api-client";
import { useI18n } from "@/lib/i18n";
import { Btn, Glass } from "@/components/aurora/primitives";

type Settings = Record<string, unknown>;

/** Phone push (Bark): where risky agent operations, finished tasks, problems and reminders go. */
export default function NotifySettings() {
  const { t } = useI18n();
  const n = t.notify;
  const [settings, setSettings] = useState<Settings | null>(null);
  const [url, setUrl] = useState("");
  const [busy, setBusy] = useState(false);
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

  const configured = settings?.bark_configured === true;
  const switches: { key: string; title: string; hint: string }[] = [
    { key: "notify_risky", title: n.risky, hint: n.riskyHint },
    { key: "notify_task_done", title: n.taskDone, hint: n.taskDoneHint },
    { key: "notify_health", title: n.health, hint: n.healthHint },
    { key: "notify_learning", title: n.learning, hint: n.learningHint },
    { key: "notify_todo", title: n.todo, hint: n.todoHint },
  ];

  return (
    <Glass padding={22} radius={20} style={{ marginBottom: 20 }}>
      <div className="mb-3 p-3 rounded-xl bg-[var(--aurora-chip)] border border-[var(--aurora-border)] text-xs text-[var(--aurora-fg3)] leading-relaxed space-y-1">
        <div>🍎 <b>iPhone / iOS</b>：在 App Store 安装 <b>Bark</b>，填入 <code>https://api.day.app/Key</code>，享有苹果原生 APNs 秒级弹窗与紧急时效通知。</div>
        <div>🤖 <b>Android 手机</b>：安装 <b>ntfy</b>（各市场或 GitHub），填入 <code>https://ntfy.sh/你的频道名</code>，无需 Google 框架即可常驻原生响铃通知。</div>
      </div>
      {settings && (
        <p style={{ fontSize: 12.5, margin: "0 0 8px", color: configured ? "#10B981" : "var(--aurora-fg3)" }}>
          {configured ? `${n.current}${String(settings.bark_masked ?? "")}` : n.notSet}
        </p>
      )}
      <input
        value={url}
        onChange={(e) => setUrl(e.target.value)}
        placeholder={configured ? n.replaceHint : "iOS 填 https://api.day.app/…  或 Android 填 https://ntfy.sh/…"}
        autoCorrect="off"
        style={{
          width: "100%",
          fontSize: 13,
          padding: "8px 10px",
          borderRadius: 10,
          border: "1px solid var(--aurora-border-strong)",
          background: "var(--aurora-surface-solid)",
          color: "var(--aurora-fg1)",
        }}
      />
      <div style={{ display: "flex", gap: 8, marginTop: 10, flexWrap: "wrap" }}>
        <Btn size="sm" disabled={busy || !url.trim()} onClick={() => save(url.trim())}>
          {n.save}
        </Btn>
        <Btn variant="glass" size="sm" disabled={busy || !configured} onClick={test}>
          {n.test}
        </Btn>
        {configured && (
          <Btn variant="ghost" size="sm" disabled={busy} onClick={() => save("")}>
            {n.clear}
          </Btn>
        )}
      </div>
      {settings &&
        switches.map((s) => (
          <label key={s.key} style={{ display: "flex", gap: 12, alignItems: "flex-start", padding: "12px 0 0", cursor: "pointer" }}>
            <input
              type="checkbox"
              checked={settings[s.key] !== false}
              disabled={busy}
              onChange={(e) => toggle(s.key, e.target.checked)}
              style={{ marginTop: 3, width: 15, height: 15, accentColor: "var(--aurora-accent)" }}
            />
            <span>
              <span style={{ display: "block", fontSize: 14, color: "var(--aurora-fg1)" }}>{s.title}</span>
              <span style={{ display: "block", fontSize: 12, color: "var(--aurora-fg3)", marginTop: 2 }}>{s.hint}</span>
            </span>
          </label>
        ))}
      {message && <p style={{ margin: "12px 0 0", fontSize: 12.5, color: message.error ? "#DC2626" : "var(--aurora-fg2)" }}>{message.text}</p>}
    </Glass>
  );
}
