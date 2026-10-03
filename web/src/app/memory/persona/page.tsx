"use client";

import { useCallback, useEffect, useMemo, useState } from "react";
import { api, ProfileDevice, ProfileState, ProfileVersion } from "@/lib/api-client";
import { fmt, useI18n } from "@/lib/i18n";
import { BrandMark } from "@/components/aurora/BrandMark";
import { Btn, Chip, Glass, TopBar } from "@/components/aurora/primitives";
import { Icon } from "@/components/aurora/Icon";
import MarkdownViewer from "@/components/viewers/MarkdownViewer";
import LearnedCorrections from "@/components/persona/LearnedCorrections";
import CognitiveCompass from "@/components/memory/CognitiveCompass";

const TARGET_META: Record<string, { label: string; file: string }> = {
  claude_code: { label: "Claude Code", file: "~/.claude/CLAUDE.md" },
  codex: { label: "Codex", file: "~/.codex/AGENTS.md" },
  antigravity: { label: "Antigravity / Gemini", file: "~/.gemini/GEMINI.md" },
  openclaw: { label: "OpenClaw", file: "~/.openclaw/workspace/USER.md" },
  hermes: { label: "Hermes", file: "~/.hermes/SOUL.md" },
};

type Tone = "neutral" | "accent" | "success" | "warn" | "danger";

interface PersonaSection {
  title: string;
  icon: "message" | "zap" | "devices" | "sparkles" | "check";
  accent: string;
  items: string[];
}

function parsePersonaSections(content: string | undefined): PersonaSection[] {
  if (!content) return [];
  const lines = content.split("\n");
  const rawSections: Array<{ title: string; items: string[] }> = [];
  let currentTitle = "核心准则";
  let currentItems: string[] = [];

  for (const line of lines) {
    const trimmed = line.trim();
    if (trimmed.startsWith("### ")) {
      if (currentItems.length > 0) {
        rawSections.push({ title: currentTitle, items: currentItems });
        currentItems = [];
      }
      currentTitle = trimmed.replace(/^###\s+/, "").trim();
    } else if (trimmed.startsWith("## ")) {
      // 忽略总标题
    } else if (trimmed.startsWith("- ")) {
      currentItems.push(trimmed.replace(/^-\s+/, "").trim());
    }
  }
  if (currentItems.length > 0) {
    rawSections.push({ title: currentTitle, items: currentItems });
  }

  return rawSections.map((sec) => {
    let icon: PersonaSection["icon"] = "check";
    let accent = "var(--aurora-accent)";
    if (/沟通|回复|对话/i.test(sec.title)) {
      icon = "message";
      accent = "#8B5CF6";
    } else if (/铁律|红线|避坑|规矩/i.test(sec.title)) {
      icon = "zap";
      accent = "#EF4444";
    } else if (/技术|架构|性能|偏好/i.test(sec.title)) {
      icon = "devices";
      accent = "#3B82F6";
    } else if (/工作|方式|流程/i.test(sec.title)) {
      icon = "sparkles";
      accent = "#10B981";
    }
    return {
      title: sec.title,
      icon,
      accent,
      items: sec.items,
    };
  });
}

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
                padding: "8px 14px",
                borderRadius: 14,
                cursor: "pointer",
                border: `1px solid ${on ? "var(--aurora-accent)" : "var(--aurora-border)"}`,
                background: on ? "var(--aurora-surface-solid)" : "var(--aurora-chip)",
                color: on ? "var(--aurora-fg1)" : "var(--aurora-fg3)",
                fontSize: 12.5,
                textAlign: "left",
                boxShadow: on ? "0 2px 10px rgba(109, 40, 217, 0.12)" : "none",
              }}
            >
              <BrandMark id={tool} size={16} colored={on} tint={on ? undefined : "var(--aurora-fg3)"} />
              <span style={{ display: "flex", flexDirection: "column", lineHeight: 1.25 }}>
                <span style={{ fontWeight: on ? 600 : 500, display: "flex", alignItems: "center", gap: 5 }}>
                  {TARGET_META[tool]?.label || tool}
                  {on && (
                    <span className="w-1.5 h-1.5 rounded-full bg-[#10B981] breathing-glow-emerald inline-block" />
                  )}
                </span>
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
  const [pending, setPending] = useState<Record<string, unknown>[]>([]);
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState<"regenerate" | "publish" | "save" | "discard" | null>(null);
  const [notice, setNotice] = useState<string | null>(null);
  const [editing, setEditing] = useState<"draft" | "published" | null>(null);
  const [showAdvancedEditor, setShowAdvancedEditor] = useState(false);

  const load = useCallback(async () => {
    try {
      const [profile, corrections] = await Promise.all([
        api.getProfile(),
        api.getCorrections().catch(() => ({}) as Record<string, unknown>),
      ]);
      setState(profile);
      setPending(Array.isArray(corrections.pending) ? (corrections.pending as Record<string, unknown>[]) : []);
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
  const activeContent = draft ? draft.content : published ? published.content : "";
  const structuredSections = useMemo(() => parsePersonaSections(activeContent), [activeContent]);

  // Total targets across all devices
  const syncedTargetsCount = useMemo(() => {
    if (!state?.devices) return 0;
    const set = new Set<string>();
    state.devices.forEach((d) => d.targets.forEach((tg) => set.add(tg)));
    return set.size;
  }, [state?.devices]);

  const statsLine = (p: ProfileVersion) => {
    const v = p.stats.user_voice;
    if (!v) return null;
    return fmt(t.persona.voiceStats, { kept: v.kept, corrections: v.corrections, memories: p.stats.memories ?? 0 });
  };

  return (
    <div className="w-full max-w-5xl mx-auto pb-16 min-w-0">
      {/* Global Cognitive Compass Navigation */}
      <CognitiveCompass
        currentTab="persona"
        summaryStats={{
          personaVersion: published?.version ?? undefined,
          syncedTargetsCount: syncedTargetsCount || 5,
        }}
      />

      <TopBar
        title="个人画像 · 行为与铁律"
        subtitle="AI 怎么为你做事 · 自动提炼风格习惯，实时注入本地各大 AI 客户端"
        right={
          <div className="flex items-center gap-2">
            <Btn
              variant="glass"
              size="sm"
              icon="refresh"
              onClick={regenerate}
              disabled={busy !== null}
            >
              {busy === "regenerate" ? t.persona.regenerating : "AI 重新提炼画像"}
            </Btn>
            {draft && (
              <Btn
                size="sm"
                icon="rocket"
                onClick={() => run("publish", () => api.publishProfile())}
                disabled={busy !== null}
              >
                {busy === "publish" ? t.persona.publishing : "发布新版本"}
              </Btn>
            )}
          </div>
        }
      />

      {error && (
        <Glass padding={14} radius={14} style={{ marginBottom: 14, color: "#DC2626", fontSize: 13 }}>
          {error}
        </Glass>
      )}
      {notice && (
        <Glass padding={14} radius={14} style={{ marginBottom: 14, color: "var(--aurora-fg2)", fontSize: 13 }}>
          {notice}
        </Glass>
      )}

      {/* Learned Corrections - 避坑自学习 */}
      <LearnedCorrections
        topics={pending}
        onChanged={(message) => {
          setNotice(message ?? null);
          load();
        }}
      />

      {/* ─────────────────────────────────────────────────────────────
          1. AI 眼中的我 · 结构化画像卡片画廊 (Structured Persona Gallery)
          ───────────────────────────────────────────────────────────── */}
      <div className="mb-6">
        <div className="flex items-center justify-between mb-3 px-1">
          <div className="flex items-center gap-2">
            <span className="text-xs font-bold text-[var(--aurora-fg1)] uppercase tracking-wider">
              AI 视角画像总览
            </span>
            <span className="text-[11px] text-[var(--aurora-fg3)]">
              （当前生效版本 v{published?.version ?? 1} · {structuredSections.reduce((acc, s) => acc + s.items.length, 0)} 条行为准则）
            </span>
          </div>

          <button
            onClick={() => setShowAdvancedEditor((v) => !v)}
            className="text-xs text-[var(--aurora-accent)] hover:underline flex items-center gap-1 font-medium"
          >
            <Icon name={showAdvancedEditor ? "close" : "edit"} size={13} />
            <span>{showAdvancedEditor ? "收起代码比对" : "展开高级代码与 Diff"}</span>
          </button>
        </div>

        {structuredSections.length > 0 ? (
          <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
            {structuredSections.map((sec, idx) => (
              <div
                key={idx}
                className="p-4 rounded-2xl border border-[var(--aurora-border)] bg-[var(--aurora-surface)] shadow-xs transition-all hover:border-[var(--aurora-border-strong)]"
              >
                <div className="flex items-center gap-2.5 pb-2.5 mb-2.5 border-b border-[var(--aurora-border)]">
                  <div
                    className="w-7 h-7 rounded-xl flex items-center justify-center"
                    style={{ backgroundColor: `${sec.accent}14`, color: sec.accent }}
                  >
                    <Icon name={sec.icon} size={15} />
                  </div>
                  <h3 className="text-sm font-semibold text-[var(--aurora-fg1)]">
                    {sec.title}
                  </h3>
                  <span className="ml-auto text-[10px] font-mono px-2 py-0.5 rounded-full bg-[var(--aurora-chip)] text-[var(--aurora-fg3)]">
                    {sec.items.length} 条准则
                  </span>
                </div>

                <div className="space-y-2.5">
                  {sec.items.map((item, itemIdx) => (
                    <div
                      key={itemIdx}
                      className="p-3 rounded-xl bg-[var(--aurora-surface-solid)] border border-[var(--aurora-border)] shadow-xs hover:border-[var(--aurora-border-strong)] transition-all flex items-start gap-2.5 text-xs text-[var(--aurora-fg2)] leading-relaxed"
                    >
                      <span
                        className="w-4 h-4 rounded-md flex items-center justify-center shrink-0 font-mono text-[10px] font-bold mt-0.5"
                        style={{
                          backgroundColor: `${sec.accent}18`,
                          color: sec.accent,
                        }}
                      >
                        {itemIdx + 1}
                      </span>
                      <span className="flex-1 font-normal select-text">
                        {item}
                      </span>
                    </div>
                  ))}
                </div>
              </div>
            ))}
          </div>
        ) : (
          <Glass padding={20} radius={16} className="text-center text-xs text-[var(--aurora-fg3)]">
            暂无已沉淀画像规则，请点击右上角「AI 重新提炼画像」启动分析。
          </Glass>
        )}
      </div>

      {/* ─────────────────────────────────────────────────────────────
          2. 跨端守护矩阵与生效终端 (Where it gets written)
          ───────────────────────────────────────────────────────────── */}
      <Glass padding="clamp(16px, 3vw, 22px)" radius={18} style={{ marginBottom: 16 }}>
        <div className="flex items-center justify-between mb-2">
          <div style={{ fontWeight: 600, color: "var(--aurora-fg1)", fontSize: 14.5 }}>
            {t.persona.devicesTitle || "全域 AI 终端守护与规则同步"}
          </div>
          <span className="text-[11px] font-medium text-[#10B981] bg-[rgba(16,185,129,0.12)] px-2.5 py-0.5 rounded-full">
            已实现实时热注入
          </span>
        </div>
        <p style={{ margin: "0 0 10px", fontSize: 12.5, color: "var(--aurora-fg3)", lineHeight: 1.5 }}>
          您在此保存的画像规则，将由 Memento 本地守护程序直接热写入本机的各大开发环境配置文件中。任何支持的 AI 工具都将遵循您的行为守则。
        </p>

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

      {/* ─────────────────────────────────────────────────────────────
          3. 高级代码编辑与版本比对 (收折区，避免干扰视觉)
          ───────────────────────────────────────────────────────────── */}
      {(showAdvancedEditor || draft) && (
        <div className="space-y-4 pt-2">
          {/* Draft awaiting review */}
          {draft && (
            <Glass
              padding="clamp(14px, 3vw, 22px)"
              radius={18}
              style={{ border: "1px solid var(--aurora-accent)" }}
            >
              <div style={{ display: "flex", alignItems: "center", gap: 8, marginBottom: 12, flexWrap: "wrap" }}>
                <Chip tone="accent" icon="edit">{t.persona.draft}</Chip>
                <span style={{ fontSize: 12, color: "var(--aurora-fg4)" }}>{formatTime(draft.updated_at)}</span>
                {statsLine(draft) && (
                  <span style={{ fontSize: 12, color: "var(--aurora-fg3)" }}>· {statsLine(draft)}</span>
                )}
              </div>

              {editing === "draft" ? (
                <ProfileEditor initial={draft.content} onSave={saveDraft} onCancel={() => setEditing(null)} busy={busy !== null} />
              ) : (
                <>
                  {draft.stats.edited_by_user && (
                    <p style={{ margin: "0 0 10px", fontSize: 12.5, color: "var(--aurora-fg3)" }}>{t.persona.editedHint}</p>
                  )}
                  {diff && published && (diff.added.length > 0 || diff.removed.length > 0) && (
                    <div style={{ marginBottom: 14, fontSize: 13, lineHeight: 1.6, padding: 12, borderRadius: 10, background: "var(--aurora-chip)" }}>
                      <div style={{ fontWeight: 600, color: "var(--aurora-fg2)", marginBottom: 6 }}>{t.persona.diffTitle}</div>
                      {diff.added.map((l) => (
                        <div key={`+${l}`} style={{ color: "#10B981" }}>+ {l.slice(2)}</div>
                      ))}
                      {diff.removed.map((l) => (
                        <div key={`-${l}`} style={{ color: "#DC2626", textDecoration: "line-through" }}>− {l.slice(2)}</div>
                      ))}
                    </div>
                  )}
                  <div className="prose prose-sm max-w-none" style={{ fontSize: 13 }}>
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
            </Glass>
          )}

          {/* Currently published raw markdown */}
          <Glass padding="clamp(14px, 3vw, 22px)" radius={18}>
            <div style={{ display: "flex", alignItems: "center", gap: 8, marginBottom: 12, flexWrap: "wrap" }}>
              <Chip tone={published ? "success" : "neutral"} icon="check">已发布原始规则文件 (Markdown)</Chip>
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
            {editing === "published" ? (
              <ProfileEditor
                initial={published?.content || "### 沟通\n- \n\n### 铁律\n- \n"}
                onSave={saveDraft}
                onCancel={() => setEditing(null)}
                busy={busy !== null}
              />
            ) : published ? (
              <div className="prose prose-sm max-w-none" style={{ fontSize: 13 }}>
                <MarkdownViewer content={published.content} />
              </div>
            ) : (
              <p style={{ margin: 0, color: "var(--aurora-fg3)", fontSize: 13.5 }}>{t.persona.noPublished}</p>
            )}
          </Glass>
        </div>
      )}
    </div>
  );
}
