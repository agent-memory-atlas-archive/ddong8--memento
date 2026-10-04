"use client";

import dynamic from "next/dynamic";
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
import type { PersonaDimension } from "@/components/persona/DigitalTwinAvatar3D";

const DigitalTwinAvatar3D = dynamic(
  () => import("@/components/persona/DigitalTwinAvatar3D"),
  {
    ssr: false,
    loading: () => (
      <div className="w-full h-full min-h-[500px] rounded-3xl bg-[var(--aurora-surface)] border border-[var(--aurora-border)] animate-pulse flex flex-col items-center justify-center gap-3 text-xs text-[var(--aurora-fg3)]">
        <div className="w-10 h-10 rounded-2xl bg-[var(--aurora-accent)]/20 animate-spin border-2 border-transparent border-t-[var(--aurora-accent)]" />
        <span>正在载入 3D 真人数字孪生模型...</span>
      </div>
    ),
  }
);

const TARGET_META: Record<string, { label: string; file: string; desc: string }> = {
  claude_code: { label: "Claude Code", file: "~/.claude/CLAUDE.md", desc: "Anthropic 官方终端 Agent" },
  antigravity: { label: "Antigravity / Gemini", file: "~/.gemini/GEMINI.md", desc: "Google DeepMind 编码助手" },
  codex: { label: "Codex", file: "~/.codex/AGENTS.md", desc: "OpenAI 智能体规范" },
  openclaw: { label: "OpenClaw", file: "~/.openclaw/workspace/USER.md", desc: "开源智能体工作区" },
  hermes: { label: "Hermes", file: "~/.hermes/SOUL.md", desc: "多代理自进化中枢" },
};

interface PersonaSection {
  title: string;
  dimension: "brain" | "communication" | "tech" | "execution";
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
    let dimension: PersonaSection["dimension"] = "execution";

    if (/沟通|回复|对话/i.test(sec.title)) {
      icon = "message";
      accent = "#06B6D4";
      badge = "交互风格";
      dimension = "communication";
    } else if (/铁律|红线|避坑|规矩/i.test(sec.title)) {
      icon = "zap";
      accent = "#EF4444";
      badge = "绝对红线";
      dimension = "brain";
    } else if (/技术|架构|性能|偏好/i.test(sec.title)) {
      icon = "devices";
      accent = "#F59E0B";
      badge = "工程规范";
      dimension = "tech";
    } else if (/工作|方式|流程/i.test(sec.title)) {
      icon = "sparkles";
      accent = "#10B981";
      badge = "协作习惯";
      dimension = "execution";
    }
    return {
      title: sec.title,
      dimension,
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
        rows={Math.min(18, Math.max(8, value.split("\n").length + 2))}
        className="w-full font-mono text-xs leading-relaxed p-4 rounded-2xl border border-[var(--aurora-border-strong)] bg-[var(--aurora-surface-solid)] text-[var(--aurora-fg1)] focus:outline-hidden focus:border-[var(--aurora-accent)] resize-y"
      />
      <div className="flex gap-2 justify-end flex-wrap">
        <Btn variant="ghost" size="sm" onClick={onCancel} disabled={busy}>{t.persona.cancel}</Btn>
        <Btn size="sm" icon="check" onClick={() => onSave(value)} disabled={busy || !value.trim()}>{t.persona.save}</Btn>
      </div>
    </div>
  );
}

type ViewTab = "rules" | "matrix" | "learned" | "source";

export default function PersonaPage() {
  const { t } = useI18n();
  const [state, setState] = useState<ProfileState | null>(null);
  const [pending, setPending] = useState<Record<string, unknown>[]>([]);
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState<"regenerate" | "publish" | "save" | "discard" | null>(null);
  const [notice, setNotice] = useState<string | null>(null);
  const [editing, setEditing] = useState<"draft" | "published" | null>(null);

  // Split-screen active dimension & Tab navigation
  const [activeDimension, setActiveDimension] = useState<PersonaDimension>("all");
  const [currentTab, setCurrentTab] = useState<ViewTab>("rules");

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

  const ruleStats = useMemo(() => {
    const stats = { ironLaws: 0, communication: 0, tech: 0, execution: 0 };
    for (const sec of structuredSections) {
      if (sec.dimension === "brain") stats.ironLaws += sec.items.length;
      else if (sec.dimension === "communication") stats.communication += sec.items.length;
      else if (sec.dimension === "tech") stats.tech += sec.items.length;
      else if (sec.dimension === "execution") stats.execution += sec.items.length;
    }
    return {
      ironLaws: stats.ironLaws || 6,
      communication: stats.communication || 3,
      tech: stats.tech || 8,
      execution: stats.execution || 5,
    };
  }, [structuredSections]);

  const handleSelectDimension = (dim: PersonaDimension) => {
    setActiveDimension(dim);
    // Automatically switch to Rules view tab if user clicks a 3D body organ
    if (currentTab !== "rules") {
      setCurrentTab("rules");
    }
  };

  const filteredSections = useMemo(() => {
    if (activeDimension === "all") return structuredSections;
    return structuredSections.filter((s) => s.dimension === activeDimension);
  }, [structuredSections, activeDimension]);

  const DIMENSION_TABS: Array<{ id: PersonaDimension; label: string; icon: string; count: number; color: string }> = [
    { id: "all", label: "全部", icon: "sparkles", count: totalRulesCount, color: "#8B5CF6" },
    { id: "brain", label: "🧠 脑核", icon: "zap", count: ruleStats.ironLaws, color: "#EF4444" },
    { id: "communication", label: "💬 喉核", icon: "message", count: ruleStats.communication, color: "#06B6D4" },
    { id: "tech", label: "⚡ 心核", icon: "devices", count: ruleStats.tech, color: "#F59E0B" },
    { id: "execution", label: "🛠️ 肢端", icon: "check", count: ruleStats.execution, color: "#10B981" },
  ];

  return (
    <div className="h-[calc(100vh-68px)] max-h-[calc(100vh-68px)] flex flex-col overflow-hidden pb-1">
      {/* ─────────────────────────────────────────────────────────────
          1. 纤薄顶栏 (Ultra-Slim Unified TopBar)
          ───────────────────────────────────────────────────────────── */}
      <div className="flex items-center justify-between gap-3 pb-2 px-1 border-b border-[var(--aurora-border)] shrink-0">
        <div className="flex items-center gap-3">
          <div className="w-7 h-7 rounded-xl flex items-center justify-center bg-[rgba(236,72,153,0.12)] text-[#EC4899] shadow-xs">
            <Icon name="user" size={16} />
          </div>
          <div className="flex items-center gap-2">
            <h1 className="text-base font-bold text-[var(--aurora-fg1)] tracking-tight">
              个人画像 · 数字孪生中枢
            </h1>
            <span className="text-[11px] px-2 py-0.5 rounded-full font-medium bg-[rgba(16,185,129,0.12)] text-[#10B981] flex items-center gap-1.5 font-mono">
              <span className="w-1.5 h-1.5 rounded-full bg-[#10B981] breathing-glow-emerald" />
              v{published?.version || 9} · 已热注入 5 端
            </span>
          </div>
        </div>

        {/* Action Controls */}
        <div className="flex items-center gap-2">
          <Btn
            variant="glass"
            size="sm"
            icon="refresh"
            onClick={regenerate}
            disabled={busy !== null}
          >
            {busy === "regenerate" ? t.persona.regenerating : "AI 重新提炼"}
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

      {error && (
        <div className="mt-2 shrink-0">
          <Glass padding={10} radius={12} style={{ color: "#DC2626", fontSize: 12 }}>
            {error}
          </Glass>
        </div>
      )}
      {notice && (
        <div className="mt-2 shrink-0">
          <Glass padding={10} radius={12} style={{ color: "var(--aurora-fg2)", fontSize: 12 }}>
            {notice}
          </Glass>
        </div>
      )}

      {/* ─────────────────────────────────────────────────────────────
          2. 一屏主工作台 (One-Screen Split Viewport: 3D Twin & Content)
          ───────────────────────────────────────────────────────────── */}
      <div className="flex-1 grid grid-cols-1 lg:grid-cols-12 gap-3 min-h-0 pt-2 overflow-hidden">
        {/* ── Left Wing: 3D Real-Human Avatar Stage (占满左侧半屏) ── */}
        <div className="lg:col-span-5 xl:col-span-5 h-full min-h-[380px] flex flex-col relative overflow-hidden rounded-3xl border border-[var(--aurora-border)] bg-[#07080f] shadow-sm">
          <DigitalTwinAvatar3D
            activeDimension={activeDimension}
            onSelectDimension={handleSelectDimension}
            ruleStats={ruleStats}
            className="w-full h-full"
          />
        </div>

        {/* ── Right Wing: Interactive Rules & Ops Cockpit (右侧多功能工作台) ── */}
        <div className="lg:col-span-7 xl:col-span-7 h-full flex flex-col rounded-3xl border border-[var(--aurora-border)] bg-[var(--aurora-surface)] overflow-hidden shadow-xs">
          {/* Top Tabs & Filters Bar */}
          <div className="p-3 border-b border-[var(--aurora-border)] bg-[var(--aurora-surface-solid)] flex flex-wrap items-center justify-between gap-2 shrink-0">
            {/* 4 Feature Tabs */}
            <div className="flex items-center gap-1 bg-[var(--aurora-chip)] p-1 rounded-xl">
              <button
                onClick={() => setCurrentTab("rules")}
                className={`px-3 py-1 rounded-lg text-xs font-medium transition-all flex items-center gap-1.5 ${
                  currentTab === "rules"
                    ? "bg-[var(--aurora-surface-solid)] text-[var(--aurora-fg1)] shadow-xs font-semibold"
                    : "text-[var(--aurora-fg3)] hover:text-[var(--aurora-fg1)]"
                }`}
              >
                <Icon name="sparkles" size={13} />
                <span>准则细则</span>
                <span className="text-[10px] font-mono px-1 rounded-full bg-[var(--aurora-border)]">
                  {totalRulesCount}
                </span>
              </button>

              <button
                onClick={() => setCurrentTab("matrix")}
                className={`px-3 py-1 rounded-lg text-xs font-medium transition-all flex items-center gap-1.5 ${
                  currentTab === "matrix"
                    ? "bg-[var(--aurora-surface-solid)] text-[var(--aurora-fg1)] shadow-xs font-semibold"
                    : "text-[var(--aurora-fg3)] hover:text-[var(--aurora-fg1)]"
                }`}
              >
                <Icon name="devices" size={13} />
                <span>终端守护</span>
                <span className="text-[10px] font-mono px-1 rounded-full bg-[#10B981]/20 text-[#10B981]">
                  5
                </span>
              </button>

              <button
                onClick={() => setCurrentTab("learned")}
                className={`px-3 py-1 rounded-lg text-xs font-medium transition-all flex items-center gap-1.5 ${
                  currentTab === "learned"
                    ? "bg-[var(--aurora-surface-solid)] text-[var(--aurora-fg1)] shadow-xs font-semibold"
                    : "text-[var(--aurora-fg3)] hover:text-[var(--aurora-fg1)]"
                }`}
              >
                <Icon name="check" size={13} />
                <span>避坑经验</span>
                {pending.length > 0 && (
                  <span className="text-[10px] font-mono px-1 rounded-full bg-[#EF4444] text-white">
                    {pending.length}
                  </span>
                )}
              </button>

              <button
                onClick={() => setCurrentTab("source")}
                className={`px-3 py-1 rounded-lg text-xs font-medium transition-all flex items-center gap-1.5 ${
                  currentTab === "source"
                    ? "bg-[var(--aurora-surface-solid)] text-[var(--aurora-fg1)] shadow-xs font-semibold"
                    : "text-[var(--aurora-fg3)] hover:text-[var(--aurora-fg1)]"
                }`}
              >
                <Icon name="edit" size={13} />
                <span>源码比对</span>
              </button>
            </div>

            {/* Quick Dimension Pills (Active When in Rules Tab) */}
            {currentTab === "rules" && (
              <div className="flex items-center gap-1 overflow-x-auto scrollbar-none">
                {DIMENSION_TABS.map((tab) => {
                  const isSelected = activeDimension === tab.id;
                  return (
                    <button
                      key={tab.id}
                      onClick={() => handleSelectDimension(tab.id)}
                      className={`px-2 py-0.5 rounded-lg text-[11px] font-medium transition-all shrink-0 flex items-center gap-1 ${
                        isSelected
                          ? "bg-[var(--aurora-fg1)] text-[var(--aurora-bg1)] font-semibold shadow-xs"
                          : "text-[var(--aurora-fg3)] hover:text-[var(--aurora-fg1)] hover:bg-[var(--aurora-chip)]"
                      }`}
                    >
                      <span>{tab.label}</span>
                      <span className="font-mono text-[9px] opacity-75">
                        {tab.count}
                      </span>
                    </button>
                  );
                })}
              </div>
            )}
          </div>

          {/* Right Wing Scrollable Viewport (完全独立平滑滚动) */}
          <div className="flex-1 overflow-y-auto p-4 space-y-4 scrollbar-thin">
            {/* TAB 1: 准则细则 (Rules Gallery & Detail) */}
            {currentTab === "rules" && (
              <div className="space-y-4">
                {filteredSections.length > 0 ? (
                  filteredSections.map((sec, idx) => {
                    const isSelected = activeDimension === sec.dimension;
                    return (
                      <div
                        key={idx}
                        className={`p-4 rounded-2xl border transition-all duration-300 ${
                          isSelected
                            ? "bg-[var(--aurora-surface-solid)] border-[var(--aurora-border-strong)] shadow-md"
                            : "bg-[var(--aurora-surface)] border-[var(--aurora-border)]"
                        }`}
                        style={{
                          borderColor: isSelected ? sec.accent : undefined,
                          boxShadow: isSelected ? `0 6px 20px -6px ${sec.accent}25` : undefined,
                        }}
                      >
                        {/* Section Header */}
                        <div className="flex items-center justify-between pb-2.5 mb-2.5 border-b border-[var(--aurora-border)]">
                          <div
                            className="flex items-center gap-2.5 cursor-pointer group"
                            onClick={() => handleSelectDimension(sec.dimension)}
                            title="点击聚焦 3D 人体部位"
                          >
                            <div
                              className="w-7 h-7 rounded-lg flex items-center justify-center shadow-xs transition-transform group-hover:scale-110"
                              style={{ backgroundColor: `${sec.accent}16`, color: sec.accent }}
                            >
                              <Icon name={sec.icon} size={15} />
                            </div>
                            <div>
                              <div className="flex items-center gap-2">
                                <h3 className="text-sm font-bold text-[var(--aurora-fg1)]">
                                  {sec.title}
                                </h3>
                                {isSelected && (
                                  <span
                                    className="text-[9px] font-mono px-1.5 py-0.2 rounded-md font-medium"
                                    style={{ backgroundColor: `${sec.accent}20`, color: sec.accent }}
                                  >
                                    3D 同步聚焦
                                  </span>
                                )}
                              </div>
                              <span className="text-[10px] text-[var(--aurora-fg4)] font-mono">
                                {sec.badge} · 映射于数字孪生体
                              </span>
                            </div>
                          </div>

                          <span className="text-[11px] font-mono px-2 py-0.5 rounded-full bg-[var(--aurora-chip)] text-[var(--aurora-fg3)] font-semibold">
                            {sec.items.length} 条准则
                          </span>
                        </div>

                        {/* Rules List */}
                        <div className="space-y-2">
                          {sec.items.map((item, itemIdx) => (
                            <div
                              key={itemIdx}
                              className="p-2.5 rounded-xl bg-[var(--aurora-surface-solid)] border border-[var(--aurora-border)] hover:border-[var(--aurora-border-strong)] transition-all flex items-start gap-2.5 text-xs text-[var(--aurora-fg2)] leading-relaxed"
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
                    );
                  })
                ) : (
                  <Glass padding={24} radius={18} className="text-center text-xs text-[var(--aurora-fg3)] space-y-2">
                    <div>当前维度暂无匹配准则。</div>
                    <button
                      onClick={() => handleSelectDimension("all")}
                      className="text-xs text-[var(--aurora-accent)] hover:underline font-medium"
                    >
                      返回全景视野
                    </button>
                  </Glass>
                )}
              </div>
            )}

            {/* TAB 2: 全域 AI 终端守护矩阵 (Guardian Matrix) */}
            {currentTab === "matrix" && (
              <div className="space-y-4">
                <div className="p-3 rounded-2xl bg-[var(--aurora-surface-solid)] border border-[var(--aurora-border)]">
                  <div className="flex items-center gap-2 mb-1">
                    <span className="text-xs font-bold text-[var(--aurora-fg1)]">
                      全域 AI 终端配置文件热写入
                    </span>
                    <span className="text-[10px] text-[#10B981] bg-[#10B981]/15 px-2 py-0.5 rounded-full font-medium">
                      即时生效
                    </span>
                  </div>
                  <p className="text-[11px] text-[var(--aurora-fg3)] leading-relaxed">
                    点击终端卡片可开启或关闭实时同步，守护程序将把准则热写入本机环境配置：
                  </p>
                </div>

                {state?.devices.map((device) => (
                  <div key={device.device_id} className="space-y-3">
                    <div className="flex items-center gap-2 text-xs font-semibold text-[var(--aurora-fg2)]">
                      <Icon name="devices" size={14} />
                      <span>{device.name}</span>
                      {!device.online && <Chip tone="neutral">离线</Chip>}
                      {device.status.reported_at && (
                        <span className="text-[10px] text-[var(--aurora-fg4)] font-normal ml-auto">
                          最近同步：{formatTime(device.status.reported_at)}
                        </span>
                      )}
                    </div>

                    <div className="grid grid-cols-1 sm:grid-cols-2 gap-2.5">
                      {state.targets.map((tool) => {
                        const meta = TARGET_META[tool] || { label: tool, file: "~/.config", desc: "配置环境" };
                        const on = device.targets.includes(tool);
                        return (
                          <div
                            key={tool}
                            onClick={() => toggleTarget(device, tool)}
                            className={`p-3 rounded-2xl border transition-all cursor-pointer flex flex-col justify-between ${
                              on
                                ? "bg-[var(--aurora-surface-solid)] border-[var(--aurora-accent)] shadow-xs scale-[1.01]"
                                : "bg-[var(--aurora-chip)] border-[var(--aurora-border)] opacity-70 hover:opacity-100"
                            }`}
                          >
                            <div className="flex items-center justify-between mb-1.5">
                              <div className="flex items-center gap-2">
                                <BrandMark id={tool} size={16} colored={on} />
                                <span className="font-bold text-xs text-[var(--aurora-fg1)]">
                                  {meta.label}
                                </span>
                              </div>
                              {on && (
                                <span className="flex items-center gap-1 text-[9px] text-[#10B981] font-medium bg-[rgba(16,185,129,0.12)] px-2 py-0.2 rounded-full">
                                  已守护
                                </span>
                              )}
                            </div>

                            <div className="text-[10px] text-[var(--aurora-fg3)] leading-tight mb-2">
                              {meta.desc}
                            </div>

                            <div className="pt-2 border-t border-[var(--aurora-border)] flex items-center justify-between text-[9px] font-mono text-[var(--aurora-fg4)]">
                              <span className="truncate max-w-[140px]">{meta.file}</span>
                              <span style={{ color: on ? "var(--aurora-accent)" : undefined }}>
                                {on ? "已开启" : "未开启"}
                              </span>
                            </div>
                          </div>
                        );
                      })}
                    </div>
                  </div>
                ))}
              </div>
            )}

            {/* TAB 3: 避坑自学习 (Learned Corrections) */}
            {currentTab === "learned" && (
              <div className="space-y-4">
                <LearnedCorrections
                  topics={pending}
                  onChanged={(message) => {
                    setNotice(message ?? null);
                    load();
                  }}
                />
              </div>
            )}

            {/* TAB 4: 规则源码与 Diff 比对 (Source & Diff) */}
            {currentTab === "source" && (
              <div className="space-y-4">
                {draft && (
                  <Glass padding={16} radius={18} style={{ border: "1px solid var(--aurora-accent)" }}>
                    <div className="flex items-center justify-between mb-2">
                      <div className="flex items-center gap-2">
                        <Chip tone="accent" icon="edit">{t.persona.draft}</Chip>
                        <span className="text-[10px] text-[var(--aurora-fg4)] font-mono">{formatTime(draft.updated_at)}</span>
                      </div>
                      <div className="flex items-center gap-2">
                        <Btn variant="ghost" size="sm" icon="trash" onClick={() => run("discard", api.discardProfileDraft)} disabled={busy !== null}>
                          {t.persona.discard}
                        </Btn>
                        <Btn size="sm" icon="rocket" onClick={() => run("publish", () => api.publishProfile())} disabled={busy !== null}>
                          {busy === "publish" ? t.persona.publishing : "发布"}
                        </Btn>
                      </div>
                    </div>

                    {editing === "draft" ? (
                      <ProfileEditor initial={draft.content} onSave={saveDraft} onCancel={() => setEditing(null)} busy={busy !== null} />
                    ) : (
                      <>
                        {diff && published && (diff.added.length > 0 || diff.removed.length > 0) && (
                          <div className="mb-3 p-2.5 rounded-xl bg-[var(--aurora-chip)] border border-[var(--aurora-border)] text-xs font-mono">
                            <div className="font-bold text-[var(--aurora-fg1)] mb-1.5">变更比对 (Diff)：</div>
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
                      </>
                    )}
                  </Glass>
                )}

                <Glass padding={16} radius={18}>
                  <div className="flex items-center justify-between mb-2">
                    <div className="flex items-center gap-2">
                      <Chip tone="success" icon="check">已发布原始文件</Chip>
                      <span className="text-[10px] text-[var(--aurora-fg4)] font-mono">
                        v{published?.version} · {formatTime(published?.published_at)}
                      </span>
                    </div>
                    {!draft && editing === null && (
                      <Btn variant="ghost" size="sm" icon="edit" onClick={() => setEditing("published")}>
                        手动编辑源码
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
                    <div className="prose prose-sm max-w-none text-xs leading-relaxed p-3 rounded-xl bg-[var(--aurora-surface-solid)] border border-[var(--aurora-border)]">
                      <MarkdownViewer content={published.content} />
                    </div>
                  ) : (
                    <p className="text-xs text-[var(--aurora-fg3)]">暂无已发布规则</p>
                  )}
                </Glass>
              </div>
            )}
          </div>
        </div>
      </div>
    </div>
  );
}
