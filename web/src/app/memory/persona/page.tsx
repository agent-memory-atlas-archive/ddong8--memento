"use client";

import { useCallback, useEffect, useMemo, useState } from "react";
import { api, ProfileDevice, ProfileState, ProfileVersion } from "@/lib/api-client";
import { fmt, useI18n } from "@/lib/i18n";
import { BrandMark } from "@/components/aurora/BrandMark";
import { Btn, Chip, Glass, TopBar } from "@/components/aurora/primitives";
import MarkdownViewer from "@/components/viewers/MarkdownViewer";

const TARGET_META: Record<string, { label: string; file: string }> = {
  claude_code: { label: "Claude Code", file: "~/.claude/CLAUDE.md" },
  codex: { label: "Codex", file: "~/.codex/AGENTS.md" },
  antigravity: { label: "Antigravity / Gemini", file: "~/.gemini/GEMINI.md" },
  openclaw: { label: "OpenClaw", file: "~/.openclaw/workspace/USER.md" },
  hermes: { label: "Hermes", file: "~/.hermes/SOUL.md" },
};

type Tone = "neutral" | "accent" | "success" | "warn" | "danger";

/** Bullet lines only: headings and blank lines aren't meaningful changes. */
function bulletLines(text: string | undefined): string[] {
  return (text || "").split("\n").map((l) => l.trim()).filter((l) => l.startsWith("- "));
}

function lineDiff(draft: string, published: string | undefined) {
  const before = new Set(bulletLines(published));
  const after = new Set(bulletLines(draft));
  return {
    added: [...after].filter((l) => !before.has(l)),
    removed: [...before].filter((l) => !after.has(l)),
  };
}

function formatTime(iso: string | null | undefined): string {
  return iso ? new Date(iso).toLocaleString(undefined, { month: "numeric", day: "numeric", hour: "2-digit", minute: "2-digit" }) : "";
}

function ProfileEditor({
  initial,
  onSave,
  onCancel,
  busy,
}: {
  initial: string;
  onSave: (content: string) => void;
  onCancel: () => void;
  busy: boolean;
}) {
  const { t } = useI18n();
  const [value, setValue] = useState(initial);
  return (
    <div style={{ display: "flex", flexDirection: "column", gap: 10 }}>
      <textarea
        value={value}
        onChange={(e) => setValue(e.target.value)}
        rows={Math.min(24, Math.max(10, value.split("\n").length + 2))}
        style={{
          width: "100%",
          fontFamily: "ui-monospace, SFMono-Regular, Menlo, monospace",
          fontSize: 13,
          lineHeight: 1.6,
          padding: 12,
          borderRadius: 12,
          border: "1px solid var(--aurora-border-strong)",
          background: "var(--aurora-surface-solid)",
          color: "var(--aurora-fg1)",
          resize: "vertical",
        }}
      />
      <div style={{ display: "flex", gap: 8, justifyContent: "flex-end", flexWrap: "wrap" }}>
        <Btn variant="ghost" size="sm" onClick={onCancel} disabled={busy}>{t.persona.cancel}</Btn>
        <Btn size="sm" icon="check" onClick={() => onSave(value)} disabled={busy || !value.trim()}>{t.persona.save}</Btn>
      </div>
    </div>
  );
}

function DeviceTargets({
  device,
  targets,
  publishedVersion,
  onToggle,
}: {
  device: ProfileDevice;
  targets: string[];
  publishedVersion: number | null;
  onToggle: (device: ProfileDevice, tool: string) => void;
}) {
  const { t } = useI18n();

  const statusOf = (tool: string): { text: string; tone: Tone } | null => {
    const enabled = device.targets.includes(tool);
    const result = device.status.results?.[tool];
    if (!result) return enabled ? { text: t.persona.statusPending, tone: "neutral" } : null;
    if (result.startsWith("error")) return { text: t.persona.statusError, tone: "danger" };
    if (result.startsWith("skipped")) return { text: t.persona.statusSkipped, tone: "warn" };
    if (result.startsWith("waiting")) return { text: t.persona.statusWaiting, tone: "neutral" };
    if (result === "removed") return enabled ? { text: t.persona.statusPending, tone: "neutral" } : null;
    if (!enabled) return { text: t.persona.statusPending, tone: "neutral" };
    const current = device.status.version === publishedVersion;
    if (!current) return { text: t.persona.statusPending, tone: "neutral" };
    return { text: result === "written" ? t.persona.statusWritten : t.persona.statusUnchanged, tone: "success" };
  };

  return (
    <div style={{ padding: "12px 0", borderTop: "1px solid var(--aurora-border)" }}>
      <div style={{ display: "flex", alignItems: "center", gap: 8, marginBottom: 10, flexWrap: "wrap" }}>
        <span style={{ fontWeight: 600, color: "var(--aurora-fg1)", fontSize: 13.5 }}>{device.name}</span>
        {!device.online && <Chip tone="neutral">{t.persona.offline}</Chip>}
        {device.status.reported_at && (
          <span style={{ fontSize: 11.5, color: "var(--aurora-fg4)" }}>
            {t.persona.reportedAt} {formatTime(device.status.reported_at)}
          </span>
        )}
      </div>
      <div style={{ display: "flex", gap: 8, flexWrap: "wrap" }}>
        {targets.map((tool) => {
          const on = device.targets.includes(tool);
          const status = statusOf(tool);
          const error = device.status.results?.[tool]?.startsWith("error") ? device.status.results[tool] : undefined;
          return (
            <button
              key={tool}
              type="button"
              onClick={() => onToggle(device, tool)}
              title={error || TARGET_META[tool]?.file}
              aria-pressed={on}
              style={{
                display: "inline-flex",
                alignItems: "center",
                gap: 8,
                padding: "7px 12px",
                borderRadius: 12,
                cursor: "pointer",
                border: `1px solid ${on ? "var(--aurora-accent)" : "var(--aurora-border)"}`,
                background: on ? "var(--aurora-accent-soft)" : "var(--aurora-chip)",
                color: on ? "var(--aurora-fg1)" : "var(--aurora-fg3)",
                fontSize: 12.5,
                textAlign: "left",
              }}
            >
              <BrandMark id={tool} size={15} colored={on} tint={on ? undefined : "var(--aurora-fg3)"} />
              <span style={{ display: "flex", flexDirection: "column", lineHeight: 1.25 }}>
                <span style={{ fontWeight: on ? 600 : 500 }}>{TARGET_META[tool]?.label || tool}</span>
                <span style={{ fontSize: 10.5, color: "var(--aurora-fg4)", fontFamily: "ui-monospace, monospace" }}>
                  {TARGET_META[tool]?.file}
                </span>
              </span>
              {status && <Chip tone={status.tone} style={{ marginLeft: 4 }}>{status.text}</Chip>}
            </button>
          );
        })}
      </div>
    </div>
  );
}

export default function PersonaPage() {
  const { t } = useI18n();
  const [state, setState] = useState<ProfileState | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState<"regenerate" | "publish" | "save" | "discard" | null>(null);
  const [notice, setNotice] = useState<string | null>(null);
  const [editing, setEditing] = useState<"draft" | "published" | null>(null);

  const load = useCallback(async () => {
    try {
      setState(await api.getProfile());
      setError(null);
    } catch (e) {
      setError((e as Error).message);
    }
  }, []);

  useEffect(() => {
    load();
  }, [load]);

  const run = async (kind: NonNullable<typeof busy>, fn: () => Promise<unknown>) => {
    setBusy(kind);
    setNotice(null);
    try {
      await fn();
      await load();
    } catch (e) {
      setError((e as Error).message);
    } finally {
      setBusy(null);
    }
  };

  const regenerate = () =>
    run("regenerate", async () => {
      const res = await api.regenerateProfileDraft();
      const messages: Record<string, string> = {
        same_as_published: t.persona.unchanged,
        no_input: t.persona.noInput,
        llm_failed: t.persona.llmFailed,
        no_llm: t.persona.noLlm,
        user_editing: t.persona.userEditing,
      };
      if (res.status !== "updated") setNotice(messages[res.status] ?? res.status);
    });

  const saveDraft = (content: string) =>
    run("save", async () => {
      await api.saveProfileDraft(content);
      setEditing(null);
    });

  const toggleTarget = async (device: ProfileDevice, tool: string) => {
    const next = device.targets.includes(tool)
      ? device.targets.filter((x) => x !== tool)
      : [...device.targets, tool];
    // Optimistic: flip immediately, reconcile with the server's answer.
    setState((s) => s && {
      ...s,
      devices: s.devices.map((d) => (d.device_id === device.device_id ? { ...d, targets: next } : d)),
    });
    try {
      await api.setProfileTargets(device.device_id, next);
    } catch (e) {
      setError((e as Error).message);
    }
    load();
  };

  const draft = state?.draft ?? null;
  const published = state?.published ?? null;
  const diff = useMemo(() => (draft ? lineDiff(draft.content, published?.content) : null), [draft, published]);

  const statsLine = (p: ProfileVersion) => {
    const v = p.stats.user_voice;
    if (!v) return null;
    return fmt(t.persona.voiceStats, { kept: v.kept, corrections: v.corrections, memories: p.stats.memories ?? 0 });
  };

  return (
    <div className="w-full max-w-4xl mx-auto pb-16 min-w-0">
      <TopBar
        title={t.persona.title}
        subtitle={t.persona.subtitle}
        right={
          <Btn variant="glass" size="sm" icon="refresh" onClick={regenerate} disabled={busy !== null}>
            {busy === "regenerate" ? t.persona.regenerating : t.persona.regenerate}
          </Btn>
        }
      />

      {error && (
        <Glass padding={14} radius={14} style={{ marginBottom: 14, color: "#DC2626", fontSize: 13 }}>{error}</Glass>
      )}
      {notice && (
        <Glass padding={14} radius={14} style={{ marginBottom: 14, color: "var(--aurora-fg2)", fontSize: 13 }}>{notice}</Glass>
      )}

      {/* Draft awaiting review */}
      <Glass
        padding="clamp(14px, 3vw, 22px)"
        radius={18}
        style={{ marginBottom: 16, ...(draft ? { border: "1px solid var(--aurora-accent)" } : {}) }}
      >
        <div style={{ display: "flex", alignItems: "center", gap: 8, marginBottom: 12, flexWrap: "wrap" }}>
          <Chip tone={draft ? "accent" : "neutral"} icon="edit">{t.persona.draft}</Chip>
          {draft && <span style={{ fontSize: 12, color: "var(--aurora-fg4)" }}>{formatTime(draft.updated_at)}</span>}
          {draft && statsLine(draft) && (
            <span style={{ fontSize: 12, color: "var(--aurora-fg3)" }}>· {statsLine(draft)}</span>
          )}
        </div>

        {!draft && editing !== "published" && (
          <p style={{ margin: 0, color: "var(--aurora-fg3)", fontSize: 13.5 }}>{t.persona.noDraft}</p>
        )}

        {draft && editing === "draft" && (
          <ProfileEditor initial={draft.content} onSave={saveDraft} onCancel={() => setEditing(null)} busy={busy !== null} />
        )}

        {draft && editing !== "draft" && (
          <>
            {draft.stats.edited_by_user && (
              <p style={{ margin: "0 0 10px", fontSize: 12.5, color: "var(--aurora-fg3)" }}>{t.persona.editedHint}</p>
            )}
            {diff && published && (diff.added.length > 0 || diff.removed.length > 0) && (
              <div style={{ marginBottom: 14, fontSize: 13, lineHeight: 1.6 }}>
                <div style={{ fontWeight: 600, color: "var(--aurora-fg2)", marginBottom: 6 }}>{t.persona.diffTitle}</div>
                {diff.added.map((l) => (
                  <div key={`+${l}`} style={{ color: "#10B981" }}>+ {l.slice(2)}</div>
                ))}
                {diff.removed.map((l) => (
                  <div key={`-${l}`} style={{ color: "#DC2626", textDecoration: "line-through" }}>− {l.slice(2)}</div>
                ))}
              </div>
            )}
            <div className="prose prose-sm max-w-none" style={{ fontSize: 14 }}>
              <MarkdownViewer content={draft.content} />
            </div>
            <div style={{ display: "flex", gap: 8, justifyContent: "flex-end", marginTop: 14, flexWrap: "wrap" }}>
              <Btn variant="ghost" size="sm" icon="trash" onClick={() => run("discard", api.discardProfileDraft)} disabled={busy !== null}>
                {t.persona.discard}
              </Btn>
              <Btn variant="glass" size="sm" icon="edit" onClick={() => setEditing("draft")} disabled={busy !== null}>
                {t.persona.edit}
              </Btn>
              <Btn size="sm" icon="rocket" onClick={() => run("publish", () => api.publishProfile())} disabled={busy !== null}>
                {busy === "publish" ? t.persona.publishing : t.persona.publish}
              </Btn>
            </div>
          </>
        )}

        {editing === "published" && (
          <ProfileEditor
            initial={published?.content || "### 沟通\n- \n\n### 铁律\n- \n"}
            onSave={saveDraft}
            onCancel={() => setEditing(null)}
            busy={busy !== null}
          />
        )}
      </Glass>

      {/* Currently published */}
      <Glass padding="clamp(14px, 3vw, 22px)" radius={18} style={{ marginBottom: 16 }}>
        <div style={{ display: "flex", alignItems: "center", gap: 8, marginBottom: 12, flexWrap: "wrap" }}>
          <Chip tone={published ? "success" : "neutral"} icon="check">{t.persona.published}</Chip>
          {published && (
            <span style={{ fontSize: 12, color: "var(--aurora-fg4)" }}>
              {t.persona.version} {published.version} · {formatTime(published.published_at)}
            </span>
          )}
          {!draft && editing === null && (
            <Btn variant="ghost" size="sm" icon="edit" style={{ marginLeft: "auto" }} onClick={() => setEditing("published")}>
              {t.persona.edit}
            </Btn>
          )}
        </div>
        {published ? (
          <div className="prose prose-sm max-w-none" style={{ fontSize: 14 }}>
            <MarkdownViewer content={published.content} />
          </div>
        ) : (
          <p style={{ margin: 0, color: "var(--aurora-fg3)", fontSize: 13.5 }}>{t.persona.noPublished}</p>
        )}
      </Glass>

      {/* Where it gets written */}
      <Glass padding="clamp(14px, 3vw, 22px)" radius={18}>
        <div style={{ fontWeight: 600, color: "var(--aurora-fg1)", fontSize: 14.5, marginBottom: 4 }}>{t.persona.devicesTitle}</div>
        <p style={{ margin: "0 0 6px", fontSize: 12.5, color: "var(--aurora-fg3)", lineHeight: 1.5 }}>{t.persona.devicesHint}</p>
        {state && state.devices.length === 0 && (
          <p style={{ margin: "10px 0 0", color: "var(--aurora-fg3)", fontSize: 13 }}>{t.persona.noDevices}</p>
        )}
        {state?.devices.map((d) => (
          <DeviceTargets
            key={d.device_id}
            device={d}
            targets={state.targets}
            publishedVersion={published?.version ?? null}
            onToggle={toggleTarget}
          />
        ))}
      </Glass>
    </div>
  );
}
