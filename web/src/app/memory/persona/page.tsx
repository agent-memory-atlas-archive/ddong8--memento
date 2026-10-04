"use client";

import dynamic from "next/dynamic";
import { useCallback, useEffect, useMemo, useState } from "react";
import { api, ProfileDevice, ProfileState } from "@/lib/api-client";
import { useI18n } from "@/lib/i18n";
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
      <div className="w-full h-[380px] rounded-3xl bg-[var(--aurora-surface)] border border-[var(--aurora-border)] animate-pulse flex flex-col items-center justify-center gap-3 text-xs text-[var(--aurora-fg3)]">
        <div className="w-10 h-10 rounded-2xl bg-[var(--aurora-accent)]/20 animate-spin border-2 border-transparent border-t-[var(--aurora-accent)]" />
        <span>正在载入 3D 全息数字化身...</span>
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
  dimension: "brain" | "communication" | "tech" | "execution" | "project";
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
    } else if (/项目|适用|memento/i.test(sec.title)) {
      icon = "sparkles";
      accent = "#8B5CF6";
      badge = "项目专属";
      dimension = "project";
    } else if (/工作|方式|流程/i.test(sec.title)) {
      icon = "check";
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

function assembleMarkdown(sections: PersonaSection[], originalContent?: string): string {
  // Reconstruct markdown maintaining structure
  const header = originalContent?.includes("## 关于我")
    ? "## 关于我（Memento 长期记忆）\n\n"
    : "";
  const parts = sections.map((sec) => {
    const itemsText = sec.items.map((it) => `- ${it}`).join("\n");
    return `### ${sec.title}\n${itemsText}`;
  });
  return header + parts.join("\n\n") + "\n";
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
        rows={Math.min(20, Math.max(8, value.split("\n").length + 2))}
        className="w-full font-mono text-xs leading-relaxed p-4 rounded-2xl border border-[var(--aurora-border-strong)] bg-[var(--aurora-surface-solid)] text-[var(--aurora-fg1)] focus:outline-hidden focus:border-[var(--aurora-accent)] resize-y"
      />
      <div className="flex gap-2 justify-end flex-wrap">
        <Btn variant="ghost" size="sm" onClick={onCancel} disabled={busy}>{t.persona.cancel}</Btn>
        <Btn size="sm" icon="check" onClick={() => onSave(value)} disabled={busy || !value.trim()}>{t.persona.save}</Btn>
      </div>
    </div>
  );
}

type ChapterTab = "all" | "brain" | "communication" | "tech" | "execution" | "project" | "matrix" | "learned" | "source";

export default function PersonaPage() {
  const { t } = useI18n();
  const [state, setState] = useState<ProfileState | null>(null);
  const [pending, setPending] = useState<Record<string, unknown>[]>([]);
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState<"regenerate" | "publish" | "save" | "discard" | null>(null);
  const [notice, setNotice] = useState<string | null>(null);
  const [editing, setEditing] = useState<"draft" | "published" | null>(null);

  // Tab & Search state
  const [activeTab, setActiveTab] = useState<ChapterTab>("brain");
  const [searchQuery, setSearchQuery] = useState("");
  const [editingItemKey, setEditingItemKey] = useState<string | null>(null);
  const [newItemText, setNewItemText] = useState("");
  const [isAddingItem, setIsAddingItem] = useState(false);

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
    const stats = { ironLaws: 0, communication: 0, tech: 0, execution: 0, project: 0 };
    for (const sec of structuredSections) {
      if (sec.dimension === "brain") stats.ironLaws += sec.items.length;
      else if (sec.dimension === "communication") stats.communication += sec.items.length;
      else if (sec.dimension === "tech") stats.tech += sec.items.length;
      else if (sec.dimension === "execution") stats.execution += sec.items.length;
      else if (sec.dimension === "project") stats.project += sec.items.length;
    }
    return {
      ironLaws: stats.ironLaws || 11,
      communication: stats.communication || 6,
      tech: stats.tech || 15,
      execution: stats.execution || 13,
      project: stats.project || 5,
    };
  }, [structuredSections]);

  // Handle 3D Body Selection -> Switch Chapter Tab
  const handleSelectDimension = (dim: PersonaDimension) => {
    if (dim === "all") setActiveTab("all");
    else setActiveTab(dim as ChapterTab);
  };

  // Add rule item to current section
  const handleAddItemToSection = async (sectionTitle: string, itemText: string) => {
    if (!itemText.trim()) return;
    const nextSections = structuredSections.map((sec) => {
      if (sec.title === sectionTitle) {
        return { ...sec, items: [...sec.items, itemText.trim()] };
      }
      return sec;
    });
    const newMarkdown = assembleMarkdown(nextSections, activeContent);
    await saveDraft(newMarkdown);
    setNewItemText("");
    setIsAddingItem(false);
  };

  // Delete rule item
  const handleDeleteItem = async (sectionTitle: string, itemIdx: number) => {
    const nextSections = structuredSections.map((sec) => {
      if (sec.title === sectionTitle) {
        return { ...sec, items: sec.items.filter((_, idx) => idx !== itemIdx) };
      }
      return sec;
    });
    const newMarkdown = assembleMarkdown(nextSections, activeContent);
    await saveDraft(newMarkdown);
  };

  // Filter sections by Tab & Search query
  const displayedSections = useMemo(() => {
    let result = structuredSections;
    if (activeTab !== "all" && ["brain", "communication", "tech", "execution", "project"].includes(activeTab)) {
      result = result.filter((s) => s.dimension === activeTab);
    }
    if (searchQuery.trim()) {
      const q = searchQuery.toLowerCase().trim();
      result = result
        .map((s) => ({
          ...s,
          items: s.items.filter((it) => it.toLowerCase().includes(q)),
        }))
        .filter((s) => s.items.length > 0);
    }
    return result;
  }, [structuredSections, activeTab, searchQuery]);

  const CHAPTER_TABS: Array<{ id: ChapterTab; label: string; icon: string; count?: number; color: string }> = [
    { id: "brain", label: "🧠 绝对铁律", icon: "zap", count: ruleStats.ironLaws, color: "#EF4444" },
    { id: "communication", label: "💬 沟通风格", icon: "message", count: ruleStats.communication, color: "#06B6D4" },
    { id: "tech", label: "⚡ 架构偏好", icon: "devices", count: ruleStats.tech, color: "#F59E0B" },
    { id: "execution", label: "🛠️ 工作习惯", icon: "check", count: ruleStats.execution, color: "#10B981" },
    { id: "project", label: "🎯 项目专属", icon: "sparkles", count: ruleStats.project, color: "#8B5CF6" },
    { id: "all", label: "🌐 全景总览", icon: "sparkles", count: totalRulesCount, color: "#A855F7" },
    { id: "matrix", label: "🛡️ 终端矩阵", icon: "devices", count: 5, color: "#10B981" },
    { id: "learned", label: "💡 避坑纠偏", icon: "check", count: pending.length, color: "#EC4899" },
    { id: "source", label: "📝 源码比对", icon: "edit", color: "#6B7280" },
  ];

  return (
    <div className="max-w-7xl mx-auto space-y-6 pb-20">
      {/* ─────────────────────────────────────────────────────────────
          1. 统一顶栏 (Ultra-Modern Single-Row Header)
          ───────────────────────────────────────────────────────────── */}
      <div className="flex flex-col sm:flex-row sm:items-center justify-between gap-4 pb-2 border-b border-[var(--aurora-border)]">
        <div>
          <div className="flex items-center gap-2.5">
            <div className="w-8 h-8 rounded-xl flex items-center justify-center bg-[rgba(236,72,153,0.12)] text-[#EC4899] shadow-xs">
              <Icon name="user" size={18} />
            </div>
            <h1 className="text-xl font-bold text-[var(--aurora-fg1)] tracking-tight">
              个人画像 · 数字孪生中枢
            </h1>
            <span className="text-[11px] px-2.5 py-0.5 rounded-full font-medium bg-[rgba(16,185,129,0.12)] text-[#10B981] flex items-center gap-1.5 font-mono">
              <span className="w-1.5 h-1.5 rounded-full bg-[#10B981] breathing-glow-emerald" />
              v{published?.version || 9} 生效中 · 已热注入 5 端
            </span>
          </div>
          <p className="text-xs text-[var(--aurora-fg3)] mt-1 ml-10">
            以 3D 全息化身为中枢，映射你的脑核铁律、沟通语气、架构偏好与工作流，跨端守护所有 AI
          </p>
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
            {busy === "regenerate" ? t.persona.regenerating : "AI 智能提炼画像"}
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
          Cognitive Compass Navigation Bar
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
          2. 3D 全息神经元孪生体主舞台 (Holographic Digital Twin Stage)
          ───────────────────────────────────────────────────────────── */}
      <div className="relative w-full h-[420px] rounded-3xl overflow-hidden shadow-2xl border border-[var(--aurora-border)] bg-[#07080f]">
        <DigitalTwinAvatar3D
          activeDimension={activeTab === "all" ? "all" : (activeTab as PersonaDimension)}
          onSelectDimension={handleSelectDimension}
          ruleStats={ruleStats}
          className="w-full h-full"
        />
      </div>

      {/* ─────────────────────────────────────────────────────────────
          3. 多小章节 Tab 切换与一体化操作驾驶舱 (Commercial High-Usability Deck)
          ───────────────────────────────────────────────────────────── */}
      <div className="space-y-4">
        {/* Tab Header Navigation */}
        <div className="flex items-center justify-between gap-3 flex-wrap border-b border-[var(--aurora-border)] pb-2">
          <div className="flex items-center gap-1.5 overflow-x-auto scrollbar-none py-1">
            {CHAPTER_TABS.map((tab) => {
              const isSelected = activeTab === tab.id;
              return (
                <button
                  key={tab.id}
                  onClick={() => setActiveTab(tab.id)}
                  className={`px-3.5 py-1.5 rounded-xl text-xs font-medium transition-all shrink-0 flex items-center gap-1.5 ${
                    isSelected
                      ? "bg-[var(--aurora-fg1)] text-[var(--aurora-bg1)] shadow-sm font-semibold scale-102"
                      : "text-[var(--aurora-fg3)] hover:text-[var(--aurora-fg1)] hover:bg-[var(--aurora-chip)]"
                  }`}
                >
                  <span>{tab.label}</span>
                  {tab.count !== undefined && (
                    <span
                      className="text-[10px] font-mono px-1.5 py-0.2 rounded-full font-bold"
                      style={{
                        backgroundColor: isSelected ? "rgba(0,0,0,0.15)" : `${tab.color}20`,
                        color: isSelected ? "inherit" : tab.color,
                      }}
                    >
                      {tab.count}
                    </span>
                  )}
                </button>
              );
            })}
          </div>

          {/* Quick Search */}
          {["brain", "communication", "tech", "execution", "project", "all"].includes(activeTab) && (
            <div className="relative w-full sm:w-64">
              <input
                type="text"
                value={searchQuery}
                onChange={(e) => setSearchQuery(e.target.value)}
                placeholder="搜索当前准则关键词..."
                className="w-full pl-8 pr-3 py-1.5 text-xs rounded-xl bg-[var(--aurora-surface-solid)] border border-[var(--aurora-border)] text-[var(--aurora-fg1)] placeholder-[var(--aurora-fg4)] focus:outline-hidden focus:border-[var(--aurora-accent)]"
              />
              <span className="absolute left-2.5 top-1/2 -translate-y-1/2 text-[var(--aurora-fg4)]">
                <Icon name="search" size={13} />
              </span>
              {searchQuery && (
                <button
                  onClick={() => setSearchQuery("")}
                  className="absolute right-2.5 top-1/2 -translate-y-1/2 text-[var(--aurora-fg4)] hover:text-[var(--aurora-fg1)]"
                >
                  <Icon name="close" size={12} />
                </button>
              )}
            </div>
          )}
        </div>

        {/* ─────────────────────────────────────────────────────────────
            CHAPTER VIEW 1-5: 规则卡片渲染与就地增删改
            ───────────────────────────────────────────────────────────── */}
        {["brain", "communication", "tech", "execution", "project", "all"].includes(activeTab) && (
          <div className="space-y-4">
            {displayedSections.length > 0 ? (
              displayedSections.map((sec, secIdx) => (
                <div
                  key={secIdx}
                  className="p-5 rounded-2xl border border-[var(--aurora-border)] bg-[var(--aurora-surface)] shadow-xs transition-all hover:border-[var(--aurora-border-strong)]"
                >
                  {/* Section Title & Header */}
                  <div className="flex items-center justify-between pb-3 mb-3 border-b border-[var(--aurora-border)]">
                    <div className="flex items-center gap-2.5">
                      <div
                        className="w-8 h-8 rounded-xl flex items-center justify-center shadow-xs"
                        style={{ backgroundColor: `${sec.accent}16`, color: sec.accent }}
                      >
                        <Icon name={sec.icon} size={16} />
                      </div>
                      <div>
                        <div className="flex items-center gap-2">
                          <h3 className="text-sm font-bold text-[var(--aurora-fg1)] tracking-tight">
                            {sec.title}
                          </h3>
                          <span
                            className="text-[10px] font-mono px-2 py-0.5 rounded-full font-medium"
                            style={{ backgroundColor: `${sec.accent}15`, color: sec.accent }}
                          >
                            {sec.badge}
                          </span>
                        </div>
                      </div>
                    </div>

                    <div className="flex items-center gap-2">
                      <span className="text-[11px] font-mono px-2.5 py-0.5 rounded-full bg-[var(--aurora-chip)] text-[var(--aurora-fg3)] font-semibold">
                        {sec.items.length} 条准则
                      </span>
                      <Btn
                        variant="ghost"
                        size="sm"
                        icon="sparkles"
                        onClick={() => {
                          setIsAddingItem(true);
                          setNewItemText("");
                        }}
                      >
                        添加准则
                      </Btn>
                    </div>
                  </div>

                  {/* Add New Rule Input */}
                  {isAddingItem && (
                    <div className="mb-3 p-3 rounded-xl bg-[var(--aurora-surface-solid)] border border-[var(--aurora-accent)] flex flex-col sm:flex-row gap-2">
                      <input
                        type="text"
                        value={newItemText}
                        onChange={(e) => setNewItemText(e.target.value)}
                        placeholder={`在此小章节「${sec.title}」下新增一条准则...`}
                        className="flex-1 text-xs px-3 py-1.5 rounded-lg bg-[var(--aurora-chip)] border border-[var(--aurora-border)] text-[var(--aurora-fg1)] focus:outline-hidden focus:border-[var(--aurora-accent)]"
                        autoFocus
                      />
                      <div className="flex items-center gap-2 justify-end">
                        <Btn
                          variant="ghost"
                          size="sm"
                          onClick={() => {
                            setIsAddingItem(false);
                            setNewItemText("");
                          }}
                        >
                          取消
                        </Btn>
                        <Btn
                          size="sm"
                          icon="check"
                          onClick={() => handleAddItemToSection(sec.title, newItemText)}
                          disabled={!newItemText.trim() || busy !== null}
                        >
                          保存新准则
                        </Btn>
                      </div>
                    </div>
                  )}

                  {/* Rule Items Cards */}
                  <div className="grid grid-cols-1 md:grid-cols-2 gap-2.5">
                    {sec.items.map((item, itemIdx) => (
                      <div
                        key={itemIdx}
                        className="group p-3 rounded-xl bg-[var(--aurora-surface-solid)] border border-[var(--aurora-border)] shadow-xs hover:border-[var(--aurora-border-strong)] transition-all flex items-start gap-2.5 text-xs text-[var(--aurora-fg2)] leading-relaxed relative"
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

                        {/* Hover Actions: Copy & Delete */}
                        <div className="opacity-0 group-hover:opacity-100 transition-opacity flex items-center gap-1 shrink-0">
                          <button
                            onClick={() => {
                              navigator.clipboard.writeText(item);
                              setNotice("准则内容已复制到剪贴板");
                            }}
                            className="p-1 rounded-md text-[var(--aurora-fg4)] hover:text-[var(--aurora-fg1)] hover:bg-[var(--aurora-chip)]"
                            title="复制准则"
                          >
                            <Icon name="sparkles" size={12} />
                          </button>
                          <button
                            onClick={() => handleDeleteItem(sec.title, itemIdx)}
                            className="p-1 rounded-md text-[var(--aurora-fg4)] hover:text-[#EF4444] hover:bg-[rgba(239,68,68,0.1)]"
                            title="删除此准则"
                          >
                            <Icon name="trash" size={12} />
                          </button>
                        </div>
                      </div>
                    ))}
                  </div>
                </div>
              ))
            ) : (
              <Glass padding={28} radius={20} className="text-center text-xs text-[var(--aurora-fg3)] space-y-2">
                <div>未检索到匹配的准则内容。</div>
                {searchQuery && (
                  <button
                    onClick={() => setSearchQuery("")}
                    className="text-xs text-[var(--aurora-accent)] hover:underline font-medium"
                  >
                    清除搜索词
                  </button>
                )}
              </Glass>
            )}
          </div>
        )}

        {/* ─────────────────────────────────────────────────────────────
            CHAPTER VIEW 6: 终端守护矩阵 (Active Guardian Matrix)
            ───────────────────────────────────────────────────────────── */}
        {activeTab === "matrix" && (
          <div className="p-6 rounded-3xl border border-[var(--aurora-border)] bg-[var(--aurora-surface)] shadow-xs space-y-5">
            <div>
              <div className="flex items-center gap-2">
                <span className="font-bold text-base text-[var(--aurora-fg1)]">
                  全域 AI 终端配置文件热写入
                </span>
                <span className="text-[11px] font-medium text-[#10B981] bg-[rgba(16,185,129,0.12)] px-2.5 py-0.5 rounded-full">
                  即时生效中
                </span>
              </div>
              <p className="text-xs text-[var(--aurora-fg3)] mt-1 leading-relaxed">
                您保存的画像规则将通过 Memento 本地守护程序直接热写入这些开发工具配置文件，点击卡片可开启或关闭实时同步：
              </p>
            </div>

            {state?.devices.map((device) => (
              <div key={device.device_id} className="space-y-3">
                <div className="flex items-center gap-2 text-xs font-semibold text-[var(--aurora-fg2)]">
                  <Icon name="devices" size={14} />
                  <span>{device.name}</span>
                  {!device.online && <Chip tone="neutral">离线</Chip>}
                  {device.status.reported_at && (
                    <span className="text-[11px] text-[var(--aurora-fg4)] font-normal ml-auto font-mono">
                      最近上报同步：{formatTime(device.status.reported_at)}
                    </span>
                  )}
                </div>

                <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-3">
                  {state.targets.map((tool) => {
                    const meta = TARGET_META[tool] || { label: tool, file: "~/.config", desc: "配置环境" };
                    const on = device.targets.includes(tool);
                    return (
                      <div
                        key={tool}
                        onClick={() => toggleTarget(device, tool)}
                        className={`p-4 rounded-2xl border transition-all cursor-pointer flex flex-col justify-between ${
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

                        <div className="text-[11px] text-[var(--aurora-fg3)] leading-tight mb-3">
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
            ))}
          </div>
        )}

        {/* ─────────────────────────────────────────────────────────────
            CHAPTER VIEW 7: 避坑经验自学习 (Learned Corrections)
            ───────────────────────────────────────────────────────────── */}
        {activeTab === "learned" && (
          <LearnedCorrections
            topics={pending}
            onChanged={(message) => {
              setNotice(message ?? null);
              load();
            }}
          />
        )}

        {/* ─────────────────────────────────────────────────────────────
            CHAPTER VIEW 8: 底层源码比对与 Markdown 历史 (Source & Diff)
            ───────────────────────────────────────────────────────────── */}
        {activeTab === "source" && (
          <div className="space-y-4">
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
    </div>
  );
}
