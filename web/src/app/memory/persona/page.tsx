"use client";

import { useCallback, useEffect, useMemo, useState } from "react";
import Link from "next/link";
import { api, ProfileDevice, ProfileState, ProfileVersion } from "@/lib/api-client";
import { fmt, useI18n } from "@/lib/i18n";
import { BrandMark } from "@/components/aurora/BrandMark";
import { Btn, Chip, Glass } from "@/components/aurora/primitives";
import { Icon } from "@/components/aurora/Icon";
import MarkdownViewer from "@/components/viewers/MarkdownViewer";
import LearnedCorrections from "@/components/persona/LearnedCorrections";
import CognitiveCompass from "@/components/memory/CognitiveCompass";

const TARGET_META: Record<string, { label: string; file: string; desc: string }> = {
  claude_code: { label: "Claude Code", file: "~/.claude/CLAUDE.md", desc: "Anthropic 官方终端 Agent" },
  antigravity: { label: "Antigravity / Gemini", file: "~/.gemini/GEMINI.md", desc: "Google DeepMind 编码助手" },
  codex: { label: "Codex", file: "~/.codex/AGENTS.md", desc: "OpenAI 智能体规范" },
  openclaw: { label: "OpenClaw", file: "~/.openclaw/workspace/USER.md", desc: "开源智能体工作区" },
  hermes: { label: "Hermes", file: "~/.hermes/SOUL.md", desc: "多代理自进化中枢" },
};

type Tone = "neutral" | "accent" | "success" | "warn" | "danger";

interface PersonaSection {
  title: string;
  icon: "message" | "zap" | "devices" | "sparkles" | "check";
  accent: string;
  badge: string;
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
    } else if (trimmed.startsWith("- ")) {
      currentItems.push(trimmed.replace(/^-\s+/, "").trim());
    }
  }
  if (currentItems.length > 0) {
    rawSections.push({ title: currentTitle, items: currentItems });
  }

  return rawSections.map((sec) => {
    let icon: PersonaSection["icon"] = "check";
    let accent = "#8B5CF6";
    let badge = "通用准则";
    if (/沟通|回复|对话/i.test(sec.title)) {
      icon = "message";
      accent = "#8B5CF6";
      badge = "交互风格";
    } else if (/铁律|红线|避坑|规矩/i.test(sec.title)) {
      icon = "zap";
      accent = "#EF4444";
      badge = "绝对红线";
    } else if (/技术|架构|性能|偏好/i.test(sec.title)) {
      icon = "devices";
      accent = "#3B82F6";
      badge = "工程规范";
    } else if (/工作|方式|流程/i.test(sec.title)) {
      icon = "sparkles";
      accent = "#10B981";
      badge = "协作习惯";
    }
    return {
      title: sec.title,
      icon,
      accent,
      badge,
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
    <div className="flex flex-col gap-3">
      <textarea
        value={value}
        onChange={(e) => setValue(e.target.value)}
        rows={Math.min(22, Math.max(10, value.split("\n").length + 2))}
        className="w-full font-mono text-xs leading-relaxed p-4 rounded-2xl border border-[var(--aurora-border-strong)] bg-[var(--aurora-surface-solid)] text-[var(--aurora-fg1)] focus:outline-hidden focus:border-[var(--aurora-accent)] resize-y"
      />
      <div className="flex gap-2 justify-end flex-wrap">
        <Btn variant="ghost" size="sm" onClick={onCancel} disabled={busy}>{t.persona.cancel}</Btn>
        <Btn size="sm" icon="check" onClick={() => onSave(value)} disabled={busy || !value.trim()}>{t.persona.save}</Btn>
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

  const totalRulesCount = useMemo(() => {
    return structuredSections.reduce((acc, s) => acc + s.items.length, 0);
  }, [structuredSections]);

  return (
    <div className="max-w-6xl mx-auto space-y-6 pb-20">
      {/* ─────────────────────────────────────────────────────────────
          1. 统一顶栏 (Single-Row Modern Header)
          ───────────────────────────────────────────────────────────── */}
      <div className="flex flex-col sm:flex-row sm:items-center justify-between gap-4 pb-2 border-b border-[var(--aurora-border)]">
        <div>
          <div className="flex items-center gap-2.5">
            <div className="w-8 h-8 rounded-xl flex items-center justify-center bg-[rgba(236,72,153,0.1)] text-[#EC4899] shadow-xs">
              <Icon name="user" size={18} />
            </div>
            <h1 className="text-xl font-bold text-[var(--aurora-fg1)] tracking-tight">
              个人画像 · 行为与铁律
            </h1>
            <span className="text-[11px] px-2.5 py-0.5 rounded-full font-medium bg-[rgba(16,185,129,0.12)] text-[#10B981] flex items-center gap-1.5">
              <span className="w-1.5 h-1.5 rounded-full bg-[#10B981] breathing-glow-emerald" />
              已同步至全域 AI
            </span>
          </div>
          <p className="text-xs text-[var(--aurora-fg3)] mt-1 ml-10">
            AI 该怎么做事 · 习惯风格、避坑指南与跨端热注入，让所有 AI 编码工具如臂使指
          </p>
        </div>

        {/* Action Controls */}
        <div className="flex items-center gap-2 self-start sm:self-auto">
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
      </div>

      {/* ─────────────────────────────────────────────────────────────
          Cognitive Brain 3-Pillars Executive Compass Navigation
          ───────────────────────────────────────────────────────────── */}
      <CognitiveCompass
        currentTab="persona"
        summaryStats={{
          personaVersion: state?.published?.version || 9,
          syncedTargetsCount: 5,
        }}
      />

      {error && (
        <Glass padding={14} radius={14} style={{ color: "#DC2626", fontSize: 13 }}>
          {error}
        </Glass>
      )}
      {notice && (
        <Glass padding={14} radius={14} style={{ color: "var(--aurora-fg2)", fontSize: 13 }}>
          {notice}
        </Glass>
      )}

      {/* ─────────────────────────────────────────────────────────────
          2. Hero 巨幕卡 (Persona Overview Banner)
          ───────────────────────────────────────────────────────────── */}
      <div className="relative overflow-hidden rounded-3xl p-6 sm:p-8 border border-[var(--aurora-border)] bg-gradient-to-br from-[var(--aurora-surface)] via-[var(--aurora-surface)] to-[rgba(236,72,153,0.06)] shadow-sm">
        <div className="flex flex-col md:flex-row md:items-center justify-between gap-6">
          <div className="space-y-2 max-w-xl">
            <span className="text-[11px] font-mono uppercase tracking-widest text-[#EC4899] font-semibold">
              Live Persona & Iron Rules · Active
            </span>
            <h2 className="text-2xl sm:text-3xl font-extrabold text-[var(--aurora-fg1)] tracking-tight">
              这是属于你的数字化准则，全天候守护。
            </h2>
            <p className="text-xs sm:text-sm text-[var(--aurora-fg2)] leading-relaxed">
              Memento 从日常纠偏与对话中沉淀出你的偏好与红线，实时热写入本机的各大开发环境配置文件。无论你在使用哪个 AI 助手，它都能完全懂得你的规矩。
            </p>
          </div>

          {/* Quick Metrics */}
          <div className="flex gap-4 shrink-0 bg-[var(--aurora-surface-solid)] p-4 rounded-2xl border border-[var(--aurora-border)] shadow-xs">
            <div className="px-3 border-r border-[var(--aurora-border)]">
              <div className="text-[11px] text-[var(--aurora-fg3)]">生效版本</div>
              <div className="text-2xl font-bold font-mono text-[#EC4899] mt-0.5">
                v{published?.version || 5}
              </div>
            </div>
            <div className="px-3 border-r border-[var(--aurora-border)]">
              <div className="text-[11px] text-[var(--aurora-fg3)]">铁律准则</div>
              <div className="text-2xl font-bold font-mono text-[var(--aurora-fg1)] mt-0.5">
                {totalRulesCount || 18}
                <span className="text-xs font-normal text-[var(--aurora-fg4)] ml-1">条</span>
              </div>
            </div>
            <div className="px-3">
              <div className="text-[11px] text-[var(--aurora-fg3)]">已守护终端</div>
              <div className="text-2xl font-bold font-mono text-[#10B981] mt-0.5">
                5
                <span className="text-xs font-normal text-[var(--aurora-fg4)] ml-1">个</span>
              </div>
            </div>
          </div>
        </div>
      </div>

      {/* 避坑经验自学习 (Learned Corrections) */}
      <LearnedCorrections
        topics={pending}
        onChanged={(message) => {
          setNotice(message ?? null);
          load();
        }}
      />

      {/* ─────────────────────────────────────────────────────────────
          3. Bento 卡片画廊 (4 大核心画像分类)
          ───────────────────────────────────────────────────────────── */}
      <div>
        <div className="flex items-center justify-between mb-3 px-1">
          <div className="flex items-center gap-2">
            <span className="text-xs font-bold text-[var(--aurora-fg1)] uppercase tracking-wider">
              AI 视角准则画廊
            </span>
            <span className="text-[11px] text-[var(--aurora-fg3)]">
              （已沉淀 {structuredSections.length} 个维度 · {totalRulesCount} 项细则）
            </span>
          </div>

          <button
            onClick={() => setShowAdvancedEditor((v) => !v)}
            className="text-xs text-[var(--aurora-accent)] hover:underline flex items-center gap-1 font-medium"
          >
            <Icon name={showAdvancedEditor ? "close" : "edit"} size={13} />
            <span>{showAdvancedEditor ? "收起底层代码比对" : "展开底层代码与 Diff"}</span>
          </button>
        </div>

        {structuredSections.length > 0 ? (
          <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
            {structuredSections.map((sec, idx) => (
              <div
                key={idx}
                className="p-5 rounded-2xl border border-[var(--aurora-border)] bg-[var(--aurora-surface)] shadow-xs transition-all hover:border-[var(--aurora-border-strong)] flex flex-col justify-between"
              >
                <div>
                  <div className="flex items-center justify-between pb-3 mb-3 border-b border-[var(--aurora-border)]">
                    <div className="flex items-center gap-2.5">
                      <div
                        className="w-8 h-8 rounded-xl flex items-center justify-center shadow-xs"
                        style={{ backgroundColor: `${sec.accent}16`, color: sec.accent }}
                      >
                        <Icon name={sec.icon} size={16} />
                      </div>
                      <div>
                        <h3 className="text-sm font-bold text-[var(--aurora-fg1)] tracking-tight">
                          {sec.title}
                        </h3>
                        <span className="text-[10px] text-[var(--aurora-fg4)] font-mono">
                          {sec.badge}
                        </span>
                      </div>
                    </div>

                    <span className="text-[11px] font-mono px-2.5 py-0.5 rounded-full bg-[var(--aurora-chip)] text-[var(--aurora-fg3)] font-semibold">
                      {sec.items.length} 条
                    </span>
                  </div>

                  <div className="space-y-2.5">
                    {sec.items.map((item, itemIdx) => (
                      <div
                        key={itemIdx}
                        className="p-3 rounded-xl bg-[var(--aurora-surface-solid)] border border-[var(--aurora-border)] shadow-xs hover:border-[var(--aurora-border-strong)] transition-all flex items-start gap-3 text-xs text-[var(--aurora-fg2)] leading-relaxed"
                      >
                        <span
                          className="w-4 h-4 rounded-md flex items-center justify-center shrink-0 font-mono text-[10px] font-bold mt-0.5 shadow-2xs"
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
              </div>
            ))}
          </div>
        ) : (
          <Glass padding={24} radius={18} className="text-center text-xs text-[var(--aurora-fg3)]">
            暂无已沉淀画像规则，请点击右上角「AI 重新提炼画像」启动分析。
          </Glass>
        )}
      </div>

      {/* ─────────────────────────────────────────────────────────────
          4. 全域 AI 终端守护矩阵 (Active Guardian Matrix)
          ───────────────────────────────────────────────────────────── */}
      <div className="rounded-3xl p-6 border border-[var(--aurora-border)] bg-[var(--aurora-surface)] shadow-xs">
        <div className="flex flex-col sm:flex-row sm:items-center justify-between gap-2 pb-4 mb-4 border-b border-[var(--aurora-border)]">
          <div>
            <div className="flex items-center gap-2">
              <span className="font-bold text-base text-[var(--aurora-fg1)]">
                全域 AI 终端守护矩阵
              </span>
              <span className="text-[11px] font-medium text-[#10B981] bg-[rgba(16,185,129,0.12)] px-2.5 py-0.5 rounded-full">
                实时生效中
              </span>
            </div>
            <p className="text-xs text-[var(--aurora-fg3)] mt-1">
              您保存的画像规则将通过 Memento 本地守护程序直接热写入这些环境，点击卡片可开启或关闭同步：
            </p>
          </div>
        </div>

        {state?.devices.map((device) => {
          return (
            <div key={device.device_id} className="space-y-3">
              <div className="flex items-center gap-2 text-xs font-semibold text-[var(--aurora-fg2)]">
                <Icon name="devices" size={14} />
                <span>{device.name}</span>
                {!device.online && <Chip tone="neutral">离线</Chip>}
                {device.status.reported_at && (
                  <span className="text-[11px] text-[var(--aurora-fg4)] font-normal ml-auto">
                    最近上报：{formatTime(device.status.reported_at)}
                  </span>
                )}
              </div>

              <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-3">
                {state.targets.map((tool) => {
                  const meta = TARGET_META[tool] || { label: tool, file: "~/.config", desc: "配置环境" };
                  const on = device.targets.includes(tool);
                  const result = device.status.results?.[tool];
                  const isSuccess = result === "written" || result === "unchanged";

                  return (
                    <div
                      key={tool}
                      onClick={() => toggleTarget(device, tool)}
                      className={`p-3.5 rounded-2xl border transition-all cursor-pointer flex flex-col justify-between ${
                        on
                          ? "bg-[var(--aurora-surface-solid)] border-[var(--aurora-accent)] shadow-xs scale-[1.01]"
                          : "bg-[var(--aurora-chip)] border-[var(--aurora-border)] opacity-70 hover:opacity-100"
                      }`}
                    >
                      <div className="flex items-center justify-between mb-2">
                        <div className="flex items-center gap-2">
                          <BrandMark id={tool} size={18} colored={on} />
                          <span className="font-bold text-xs text-[var(--aurora-fg1)]">
                            {meta.label}
                          </span>
                        </div>
                        {on && (
                          <span className="flex items-center gap-1 text-[10px] text-[#10B981] font-medium bg-[rgba(16,185,129,0.12)] px-2 py-0.5 rounded-full">
                            <span className="w-1.5 h-1.5 rounded-full bg-[#10B981] breathing-glow-emerald" />
                            已守护
                          </span>
                        )}
                      </div>

                      <div className="text-[11px] text-[var(--aurora-fg3)] leading-tight mb-2">
                        {meta.desc}
                      </div>

                      <div className="pt-2 border-t border-[var(--aurora-border)] flex items-center justify-between text-[10px] font-mono text-[var(--aurora-fg4)]">
                        <span className="truncate max-w-[170px]">{meta.file}</span>
                        <span style={{ color: on ? "var(--aurora-accent)" : undefined }}>
                          {on ? "已激活" : "未开启"}
                        </span>
                      </div>
                    </div>
                  );
                })}
              </div>
            </div>
          );
        })}
      </div>

      {/* ─────────────────────────────────────────────────────────────
          5. 底层代码编辑与版本比对抽屉 (收纳折叠)
          ───────────────────────────────────────────────────────────── */}
      {(showAdvancedEditor || draft) && (
        <div className="space-y-4 pt-2">
          {draft && (
            <Glass
              padding="clamp(16px, 3vw, 24px)"
              radius={20}
              style={{ border: "1px solid var(--aurora-accent)" }}
            >
              <div className="flex items-center gap-2 mb-3">
                <Chip tone="accent" icon="edit">{t.persona.draft}</Chip>
                <span className="text-xs text-[var(--aurora-fg4)] font-mono">{formatTime(draft.updated_at)}</span>
              </div>

              {editing === "draft" ? (
                <ProfileEditor initial={draft.content} onSave={saveDraft} onCancel={() => setEditing(null)} busy={busy !== null} />
              ) : (
                <>
                  {diff && published && (diff.added.length > 0 || diff.removed.length > 0) && (
                    <div className="mb-4 p-3 rounded-xl bg-[var(--aurora-chip)] border border-[var(--aurora-border)] text-xs font-mono">
                      <div className="font-bold text-[var(--aurora-fg1)] mb-2">变更比对 (Diff)：</div>
                      {diff.added.map((l) => (
                        <div key={`+${l}`} className="text-[#10B981]">+ {l.slice(2)}</div>
                      ))}
                      {diff.removed.map((l) => (
                        <div key={`-${l}`} className="text-[#DC2626] line-through">− {l.slice(2)}</div>
                      ))}
                    </div>
                  )}
                  <div className="prose prose-sm max-w-none text-xs">
                    <MarkdownViewer content={draft.content} />
                  </div>
                  <div className="flex gap-2 justify-end mt-4">
                    <Btn variant="ghost" size="sm" icon="trash" onClick={() => run("discard", api.discardProfileDraft)} disabled={busy !== null}>
                      {t.persona.discard}
                    </Btn>
                    <Btn variant="glass" size="sm" icon="edit" onClick={() => setEditing("draft")} disabled={busy !== null}>
                      {t.persona.edit}
                    </Btn>
                    <Btn size="sm" icon="rocket" onClick={() => run("publish", () => api.publishProfile())} disabled={busy !== null}>
                      {busy === "publish" ? t.persona.publishing : "发布新版本"}
                    </Btn>
                  </div>
                </>
              )}
            </Glass>
          )}

          {/* Published Raw Markdown */}
          <Glass padding="clamp(16px, 3vw, 24px)" radius={20}>
            <div className="flex items-center justify-between mb-3">
              <div className="flex items-center gap-2">
                <Chip tone="success" icon="check">已发布原始规则文件 (Markdown)</Chip>
                <span className="text-xs text-[var(--aurora-fg4)] font-mono">
                  v{published?.version} · {formatTime(published?.published_at)}
                </span>
              </div>
              {!draft && editing === null && (
                <Btn variant="ghost" size="sm" icon="edit" onClick={() => setEditing("published")}>
                  手动修改规则源码
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
              <div className="prose prose-sm max-w-none text-xs leading-relaxed p-4 rounded-xl bg-[var(--aurora-surface-solid)] border border-[var(--aurora-border)]">
                <MarkdownViewer content={published.content} />
              </div>
            ) : (
              <p className="text-xs text-[var(--aurora-fg3)]">暂无已发布规则</p>
            )}
          </Glass>
        </div>
      )}
    </div>
  );
}
