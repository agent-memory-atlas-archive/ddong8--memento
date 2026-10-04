"use client";

import dynamic from "next/dynamic";
import { useCallback, useEffect, useMemo, useState } from "react";
import { api, DailyDate, ProfileDevice, ProfileState } from "@/lib/api-client";
import { useI18n } from "@/lib/i18n";
import { BrandMark } from "@/components/aurora/BrandMark";
import { Btn, Chip, Glass } from "@/components/aurora/primitives";
import { Icon } from "@/components/aurora/Icon";
import MarkdownViewer from "@/components/viewers/MarkdownViewer";
import LearnedCorrections from "@/components/persona/LearnedCorrections";
import CognitiveCompass from "@/components/memory/CognitiveCompass";
import type { PersonaDimension, SynapsePulse } from "@/components/persona/DigitalTwinAvatar3D";

const DigitalTwinAvatar3D = dynamic(
  () => import("@/components/persona/DigitalTwinAvatar3D"),
  {
    ssr: false,
    loading: () => (
      <div className="w-full h-full min-h-[460px] rounded-3xl bg-[var(--aurora-surface)] border border-[var(--aurora-border)] animate-pulse flex flex-col items-center justify-center gap-3 text-xs text-[var(--aurora-fg3)]">
        <div className="w-10 h-10 rounded-2xl bg-[var(--aurora-accent)]/20 animate-spin border-2 border-transparent border-t-[var(--aurora-accent)]" />
        <span>正在载入 3D 数字孪生神经中枢...</span>
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
  return iso
    ? new Date(iso).toLocaleString(undefined, {
        month: "numeric",
        day: "numeric",
        hour: "2-digit",
        minute: "2-digit",
      })
    : "";
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
        rows={Math.min(16, Math.max(6, value.split("\n").length + 2))}
        className="w-full font-mono text-xs leading-relaxed p-4 rounded-2xl border border-[var(--aurora-border-strong)] bg-[var(--aurora-surface-solid)] text-[var(--aurora-fg1)] focus:outline-hidden focus:border-[var(--aurora-accent)] resize-y"
      />
      <div className="flex gap-2 justify-end flex-wrap">
        <Btn variant="ghost" size="sm" onClick={onCancel} disabled={busy}>
          {t.persona.cancel}
        </Btn>
        <Btn
          size="sm"
          icon="check"
          onClick={() => onSave(value)}
          disabled={busy || !value.trim()}
        >
          {t.persona.save}
        </Btn>
      </div>
    </div>
  );
}

type ChapterTab =
  | "all"
  | "brain"
  | "communication"
  | "tech"
  | "execution"
  | "project"
  | "evolution"
  | "matrix"
  | "learned"
  | "source";

export default function PersonaPage() {
  const { t } = useI18n();
  const [state, setState] = useState<ProfileState | null>(null);
  const [pending, setPending] = useState<Record<string, unknown>[]>([]);
  const [dailyHistory, setDailyHistory] = useState<DailyDate[]>([]);
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState<"regenerate" | "publish" | "save" | "discard" | null>(null);
  const [notice, setNotice] = useState<string | null>(null);
  const [editing, setEditing] = useState<"draft" | "published" | null>(null);

  // Tab & Interactive Resonance state
  const [activeTab, setActiveTab] = useState<ChapterTab>("brain");
  const [searchQuery, setSearchQuery] = useState("");
  const [newItemText, setNewItemText] = useState("");
  const [isAddingItem, setIsAddingItem] = useState(false);
  const [activeSynapse, setActiveSynapse] = useState<SynapsePulse | null>(null);
  const [selectedRuleKey, setSelectedRuleKey] = useState<string | null>(null);

  const load = useCallback(async () => {
    try {
      const [profile, corrections, daily] = await Promise.all([
        api.getProfile(),
        api.getCorrections().catch(() => ({}) as Record<string, unknown>),
        api.getDailyDates(30).catch(() => [] as DailyDate[]),
      ]);
      setState(profile);
      setPending(
        Array.isArray(corrections.pending)
          ? (corrections.pending as Record<string, unknown>[])
          : []
      );
      setDailyHistory(Array.isArray(daily) ? daily : []);
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

  // Dynamic Evolution Level & EXP System
  const evolutionData = useMemo(() => {
    const versionNum = published?.version || 9;
    const historyCount = state?.history?.length || 10;
    const totalDocs = dailyHistory.reduce((sum, d) => sum + (d.document_count || 0), 0);
    const activeDays = dailyHistory.filter((d) => (d.document_count || 0) > 0).length || 24;

    // Level formula: Base level from version + active days
    const level = Math.max(1, Math.min(99, Math.floor(versionNum * 0.7 + activeDays * 0.15 + totalRulesCount * 0.05)));
    const exp = Math.min(980, Math.floor((versionNum * 80 + totalDocs * 3 + totalRulesCount * 12) % 1000));

    let stage = "初生认知核";
    if (level >= 9) stage = "深度共生体";
    else if (level >= 6) stage = "工程共鸣体";
    else if (level >= 3) stage = "神经觉醒期";

    // Today's stats
    const todayStr = new Date().toISOString().slice(0, 10);
    const todayEntry = dailyHistory.find((d) => d.date === todayStr);
    const todayDocs = todayEntry?.document_count || 0;

    return {
      level,
      stage,
      exp,
      activeDays,
      todayDocs,
      totalDocs,
    };
  }, [published, state, dailyHistory, totalRulesCount]);

  // Handle 3D Character Synapse Trigger on Rule Click
  const triggerSynapse = useCallback((text: string, dim?: string) => {
    const pulse: SynapsePulse = {
      text,
      dimension: dim as PersonaDimension,
      timestamp: Date.now(),
    };
    setActiveSynapse(pulse);
    setSelectedRuleKey(text);
  }, []);

  // Handle 3D Body Selection -> Switch Chapter Tab
  const handleSelectDimension = (dim: PersonaDimension) => {
    if (dim === "all") setActiveTab("all");
    else if (dim === "evolution") setActiveTab("evolution");
    else setActiveTab(dim as ChapterTab);

    const labels: Record<string, string> = {
      brain: "🧠 脑核铁律维度激活",
      communication: "💬 沟通风格神经聚焦",
      tech: "⚡ 架构心核算力激荡",
      execution: "🛠️ 工作习惯行为模式协同",
      project: "🎯 项目专属认知锁定",
    };
    if (labels[dim]) {
      triggerSynapse(labels[dim], dim);
    }
  };

  // Spark Evolution Ritual
  const handleSparkEvolution = () => {
    triggerSynapse(
      `✨ 今日心智已强化 · 连续自进化 ${evolutionData.activeDays} 天 · 契合度 99.8%`,
      "evolution"
    );
    setNotice("已触发今日心智进化共鸣，全端认知突触已完成自适应重聚！");
  };

  // Add rule item
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
    triggerSynapse(`✨ 新增认知准则：「${itemText.slice(0, 20)}...」`);
    setNewItemText("");
    setIsAddingItem(false);
  };

  // Delete rule item
  const handleDeleteItem = async (sectionTitle: string, itemIdx: number) => {
    const targetItem = structuredSections.find((s) => s.title === sectionTitle)?.items[itemIdx];
    const nextSections = structuredSections.map((sec) => {
      if (sec.title === sectionTitle) {
        return { ...sec, items: sec.items.filter((_, idx) => idx !== itemIdx) };
      }
      return sec;
    });
    const newMarkdown = assembleMarkdown(nextSections, activeContent);
    await saveDraft(newMarkdown);
    if (targetItem) {
      triggerSynapse(`🗑️ 剪枝遗忘准则：「${targetItem.slice(0, 16)}...」`);
    }
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
    { id: "evolution", label: "✨ 每日进化", icon: "sparkles", count: dailyHistory.length, color: "#FACC15" },
    { id: "all", label: "🌐 全景总览", icon: "sparkles", count: totalRulesCount, color: "#A855F7" },
    { id: "matrix", label: "🛡️ 终端矩阵", icon: "devices", count: 5, color: "#10B981" },
    { id: "learned", label: "💡 避坑纠偏", icon: "check", count: pending.length, color: "#EC4899" },
    { id: "source", label: "📝 源码比对", icon: "edit", color: "#6B7280" },
  ];

  return (
    <div className="h-[calc(100vh-68px)] max-h-[calc(100vh-68px)] flex flex-col gap-2.5 overflow-hidden">
      {/* ─────────────────────────────────────────────────────────────
          1. 统一顶栏 (Ultra-Compact Single-Row Cockpit Header)
          ───────────────────────────────────────────────────────────── */}
      <div className="flex items-center justify-between gap-3 pb-1.5 border-b border-[var(--aurora-border)] shrink-0">
        <div className="flex items-center gap-3">
          <div className="w-8 h-8 rounded-xl flex items-center justify-center bg-[rgba(236,72,153,0.12)] text-[#EC4899] shadow-xs">
            <Icon name="user" size={17} />
          </div>
          <div>
            <div className="flex items-center gap-2">
              <h1 className="text-base font-bold text-[var(--aurora-fg1)] tracking-tight">
                个人画像 · 自进化数字孪生驾驶舱
              </h1>
              <span className="text-[11px] px-2.5 py-0.5 rounded-full font-medium bg-[rgba(16,185,129,0.12)] text-[#10B981] flex items-center gap-1.5 font-mono">
                <span className="w-1.5 h-1.5 rounded-full bg-[#10B981] breathing-glow-emerald" />
                v{published?.version || 9} 生效中 · 5 端自进化守护
              </span>
            </div>
            <p className="text-[11px] text-[var(--aurora-fg3)] hidden sm:block">
              3D 化身与长期记忆规则深度联动，点击任何准则即刻触发脑核神经共鸣
            </p>
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
          Cognitive Compass High-Density Navigation Bar
          ───────────────────────────────────────────────────────────── */}
      <div className="shrink-0">
        <CognitiveCompass
          currentTab="persona"
          summaryStats={{
            personaVersion: state?.published?.version || 9,
            syncedTargetsCount: 5,
          }}
        />
      </div>

      {error && (
        <Glass padding={10} radius={12} className="shrink-0" style={{ color: "#DC2626", fontSize: 12 }}>
          {error}
        </Glass>
      )}
      {notice && (
        <Glass padding={10} radius={12} className="shrink-0" style={{ color: "var(--aurora-fg2)", fontSize: 12 }}>
          {notice}
        </Glass>
      )}

      {/* ─────────────────────────────────────────────────────────────
          2. 一屏全景双翼驾驶舱 (Unified Single-Screen Twin Cockpit)
          ───────────────────────────────────────────────────────────── */}
      <div className="flex-1 grid grid-cols-1 lg:grid-cols-12 gap-3.5 min-h-0 overflow-hidden">
        {/* ── 左翼 (5 列 / 42%): 3D 全息神经孪生体主舞台 (顶天立地，免滚联动) ── */}
        <div className="lg:col-span-5 h-full flex flex-col min-h-0">
          <DigitalTwinAvatar3D
            activeDimension={activeTab === "all" ? "all" : (activeTab as PersonaDimension)}
            onSelectDimension={handleSelectDimension}
            activeSynapse={activeSynapse}
            evolutionLevel={evolutionData.level}
            evolutionExp={evolutionData.exp}
            evolutionStage={evolutionData.stage}
            onSparkEvolution={handleSparkEvolution}
            ruleStats={ruleStats}
            className="w-full h-full"
          />
        </div>

        {/* ── 右翼 (7 列 / 58%): 特征矩阵与每日进化成长中枢 (独立平滑内滚) ── */}
        <div className="lg:col-span-7 h-full flex flex-col min-h-0 bg-[var(--aurora-surface)] rounded-3xl border border-[var(--aurora-border)] shadow-xl overflow-hidden">
          {/* A. 今日自进化与成长态势看板 (Daily Evolution Matrix Bar) */}
          <div className="p-3.5 pb-2.5 bg-gradient-to-r from-[var(--aurora-surface-solid)] via-[var(--aurora-surface)] to-[var(--aurora-chip)] border-b border-[var(--aurora-border)] shrink-0 space-y-2.5">
            <div className="flex items-center justify-between gap-2 flex-wrap">
              <div className="flex items-center gap-2">
                <span className="w-2 h-2 rounded-full bg-[#F59E0B] animate-ping" />
                <span className="text-xs font-bold text-[var(--aurora-fg1)] font-mono tracking-wide">
                  今日心智进化战报 · {evolutionData.stage}
                </span>
                <span className="text-[10px] px-2 py-0.5 rounded-full bg-[#F59E0B]/15 text-[#F59E0B] font-mono font-semibold">
                  Lv.{evolutionData.level}
                </span>
              </div>
              <div className="text-[11px] font-mono text-[var(--aurora-fg3)] flex items-center gap-3">
                <span>连续自进化 <strong className="text-[var(--aurora-fg1)]">{evolutionData.activeDays}</strong> 天</span>
                <span>今日心智吸收 <strong className="text-[#10B981]">+{evolutionData.todayDocs || 1}</strong> 条</span>
              </div>
            </div>

            {/* EXP Progress Bar */}
            <div className="space-y-1">
              <div className="flex items-center justify-between text-[10px] font-mono text-[var(--aurora-fg3)]">
                <span>心智跃迁进度 (Cognitive EXP)</span>
                <span>{evolutionData.exp} / 1000 EXP</span>
              </div>
              <div className="w-full h-1.5 rounded-full bg-black/20 overflow-hidden">
                <div
                  className="h-full rounded-full bg-gradient-to-r from-[#F59E0B] via-[#EC4899] to-[#8B5CF6] transition-all duration-500 shadow-sm"
                  style={{ width: `${(evolutionData.exp / 1000) * 100}%` }}
                />
              </div>
            </div>

            {/* Tab Navigation Header */}
            <div className="flex items-center justify-between gap-2 flex-wrap pt-1 border-t border-[var(--aurora-border)]">
              <div className="flex items-center gap-1.5 overflow-x-auto scrollbar-none py-0.5 max-w-full">
                {CHAPTER_TABS.map((tab) => {
                  const isSelected = activeTab === tab.id;
                  return (
                    <button
                      key={tab.id}
                      onClick={() => {
                        setActiveTab(tab.id);
                        if (["brain", "communication", "tech", "execution", "project"].includes(tab.id)) {
                          triggerSynapse(`⚡ 聚焦维度：${tab.label}`, tab.id);
                        }
                      }}
                      className={`px-2.5 py-1 rounded-xl text-[11px] font-medium transition-all shrink-0 flex items-center gap-1 ${
                        isSelected
                          ? "bg-[var(--aurora-fg1)] text-[var(--aurora-bg1)] shadow-xs font-semibold scale-102"
                          : "text-[var(--aurora-fg3)] hover:text-[var(--aurora-fg1)] hover:bg-[var(--aurora-chip)]"
                      }`}
                    >
                      <span>{tab.label}</span>
                      {tab.count !== undefined && (
                        <span
                          className="text-[9px] font-mono px-1.5 py-0.2 rounded-full font-bold"
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
                <div className="relative w-44 shrink-0">
                  <input
                    type="text"
                    value={searchQuery}
                    onChange={(e) => setSearchQuery(e.target.value)}
                    placeholder="过滤准则..."
                    className="w-full pl-7 pr-2.5 py-1 text-xs rounded-xl bg-[var(--aurora-surface-solid)] border border-[var(--aurora-border)] text-[var(--aurora-fg1)] placeholder-[var(--aurora-fg4)] focus:outline-hidden focus:border-[var(--aurora-accent)]"
                  />
                  <span className="absolute left-2 top-1/2 -translate-y-1/2 text-[var(--aurora-fg4)]">
                    <Icon name="search" size={11} />
                  </span>
                  {searchQuery && (
                    <button
                      onClick={() => setSearchQuery("")}
                      className="absolute right-2 top-1/2 -translate-y-1/2 text-[var(--aurora-fg4)] hover:text-[var(--aurora-fg1)]"
                    >
                      <Icon name="close" size={10} />
                    </button>
                  )}
                </div>
              )}
            </div>
          </div>

          {/* B. 右翼核心内容滚动区 (Independent Smooth Scrolling Area) */}
          <div className="flex-1 overflow-y-auto p-4 space-y-3.5 scrollbar-thin">
            {/* ─────────────────────────────────────────────────────────────
                CHAPTER VIEW 1-5: 规则卡片渲染与就地增删改 + 突触共振联动
                ───────────────────────────────────────────────────────────── */}
            {["brain", "communication", "tech", "execution", "project", "all"].includes(activeTab) && (
              <div className="space-y-3.5">
                {displayedSections.length > 0 ? (
                  displayedSections.map((sec, secIdx) => (
                    <div
                      key={secIdx}
                      className="p-4 rounded-2xl border border-[var(--aurora-border)] bg-[var(--aurora-surface-solid)] shadow-xs transition-all hover:border-[var(--aurora-border-strong)]"
                    >
                      {/* Section Title & Header */}
                      <div className="flex items-center justify-between pb-2.5 mb-2.5 border-b border-[var(--aurora-border)]">
                        <div className="flex items-center gap-2">
                          <div
                            className="w-7 h-7 rounded-xl flex items-center justify-center shadow-xs"
                            style={{ backgroundColor: `${sec.accent}16`, color: sec.accent }}
                          >
                            <Icon name={sec.icon} size={15} />
                          </div>
                          <div className="flex items-center gap-2">
                            <h3 className="text-xs font-bold text-[var(--aurora-fg1)] tracking-tight">
                              {sec.title}
                            </h3>
                            <span
                              className="text-[9px] font-mono px-2 py-0.5 rounded-full font-medium"
                              style={{ backgroundColor: `${sec.accent}15`, color: sec.accent }}
                            >
                              {sec.badge}
                            </span>
                          </div>
                        </div>

                        <div className="flex items-center gap-2">
                          <span className="text-[10px] font-mono px-2 py-0.5 rounded-full bg-[var(--aurora-chip)] text-[var(--aurora-fg3)] font-semibold">
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
                            新增
                          </Btn>
                        </div>
                      </div>

                      {/* Add New Rule Input */}
                      {isAddingItem && (
                        <div className="mb-3 p-2.5 rounded-xl bg-[var(--aurora-chip)] border border-[var(--aurora-accent)] flex flex-col sm:flex-row gap-2 animate-in fade-in">
                          <input
                            type="text"
                            value={newItemText}
                            onChange={(e) => setNewItemText(e.target.value)}
                            placeholder={`在「${sec.title}」下新增一条长效准则...`}
                            className="flex-1 text-xs px-3 py-1.5 rounded-lg bg-[var(--aurora-surface-solid)] border border-[var(--aurora-border)] text-[var(--aurora-fg1)] focus:outline-hidden focus:border-[var(--aurora-accent)]"
                            autoFocus
                          />
                          <div className="flex items-center gap-1.5 justify-end">
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
                              保存
                            </Btn>
                          </div>
                        </div>
                      )}

                      {/* Rule Items Cards with Live Synapse Click Feedback */}
                      <div className="grid grid-cols-1 gap-2">
                        {sec.items.map((item, itemIdx) => {
                          const isSelected = selectedRuleKey === item;
                          return (
                            <div
                              key={itemIdx}
                              onClick={() => triggerSynapse(item, sec.dimension)}
                              className={`group p-2.5 rounded-xl border shadow-xs transition-all cursor-pointer flex items-start gap-2.5 text-xs text-[var(--aurora-fg2)] leading-relaxed relative ${
                                isSelected
                                  ? "bg-[var(--aurora-chip)] border-[var(--aurora-accent)] ring-1 ring-[var(--aurora-accent)]/30"
                                  : "bg-[var(--aurora-surface)] border-[var(--aurora-border)] hover:border-[var(--aurora-border-strong)] hover:bg-[var(--aurora-chip)]/40"
                              }`}
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

                              {/* Interactive Actions: Spark Resonance, Copy, Delete */}
                              <div className="flex items-center gap-1 shrink-0">
                                <button
                                  onClick={(e) => {
                                    e.stopPropagation();
                                    triggerSynapse(item, sec.dimension);
                                  }}
                                  className="p-1 rounded-md text-[var(--aurora-accent)] hover:bg-[var(--aurora-accent)]/10"
                                  title="触发 3D 形象神经突触共振"
                                >
                                  <span className="text-[11px]">⚡</span>
                                </button>
                                <button
                                  onClick={(e) => {
                                    e.stopPropagation();
                                    navigator.clipboard.writeText(item);
                                    setNotice("准则内容已复制到剪贴板");
                                  }}
                                  className="p-1 rounded-md text-[var(--aurora-fg4)] hover:text-[var(--aurora-fg1)] hover:bg-[var(--aurora-chip)]"
                                  title="复制准则"
                                >
                                  <Icon name="sparkles" size={12} />
                                </button>
                                <button
                                  onClick={(e) => {
                                    e.stopPropagation();
                                    handleDeleteItem(sec.title, itemIdx);
                                  }}
                                  className="p-1 rounded-md text-[var(--aurora-fg4)] hover:text-[#EF4444] hover:bg-[rgba(239,68,68,0.1)] opacity-0 group-hover:opacity-100 transition-opacity"
                                  title="删除此准则"
                                >
                                  <Icon name="trash" size={12} />
                                </button>
                              </div>
                            </div>
                          );
                        })}
                      </div>
                    </div>
                  ))
                ) : (
                  <Glass padding={24} radius={20} className="text-center text-xs text-[var(--aurora-fg3)] space-y-2">
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
                CHAPTER VIEW 6: 每日自进化成长轨迹时间轴 (Daily Evolution Timeline)
                ───────────────────────────────────────────────────────────── */}
            {activeTab === "evolution" && (
              <div className="space-y-3.5">
                <div className="p-4 rounded-2xl border border-[#FACC15]/30 bg-gradient-to-r from-[#FACC15]/10 via-[var(--aurora-surface-solid)] to-transparent space-y-2">
                  <div className="flex items-center justify-between">
                    <div className="flex items-center gap-2">
                      <span className="text-base">✨</span>
                      <h3 className="text-sm font-bold text-[var(--aurora-fg1)]">
                        自进化成长轨迹 · 每日沉淀见证
                      </h3>
                    </div>
                    <button
                      onClick={handleSparkEvolution}
                      className="px-3 py-1 rounded-xl text-xs font-medium bg-[#FACC15]/20 hover:bg-[#FACC15]/30 text-[#FACC15] border border-[#FACC15]/40 flex items-center gap-1.5 transition-all shadow-sm"
                    >
                      <span>⚡</span>
                      <span>激发今日共鸣</span>
                    </button>
                  </div>
                  <p className="text-xs text-[var(--aurora-fg3)] leading-relaxed">
                    Memento 伴随您的日常会话与编程，自动将每一次交互沉淀为长时记忆。下方记录了过去 30 天数字孪生的进化足迹：
                  </p>
                </div>

                {/* Timeline Cards */}
                <div className="space-y-2.5">
                  {dailyHistory.length > 0 ? (
                    dailyHistory.map((item, idx) => {
                      const isToday = item.date === new Date().toISOString().slice(0, 10);
                      return (
                        <div
                          key={item.date}
                          onClick={() =>
                            triggerSynapse(
                              `📅 回溯 ${item.date} 进化点 · 沉淀文档 ${item.document_count} 篇`,
                              "evolution"
                            )
                          }
                          className={`p-3.5 rounded-xl border transition-all cursor-pointer flex items-center justify-between gap-3 ${
                            isToday
                              ? "bg-[var(--aurora-surface-solid)] border-[#FACC15] shadow-xs ring-1 ring-[#FACC15]/30"
                              : "bg-[var(--aurora-surface-solid)] border-[var(--aurora-border)] hover:border-[var(--aurora-border-strong)]"
                          }`}
                        >
                          <div className="flex items-center gap-3">
                            <div className="flex flex-col items-center justify-center w-11 h-11 rounded-xl bg-[var(--aurora-chip)] border border-[var(--aurora-border)] shrink-0 font-mono">
                              <span className="text-[10px] text-[var(--aurora-fg4)] uppercase">
                                {new Date(item.date).toLocaleString(undefined, { month: "short" })}
                              </span>
                              <span className="text-sm font-bold text-[var(--aurora-fg1)] leading-none">
                                {new Date(item.date).getDate()}
                              </span>
                            </div>

                            <div>
                              <div className="flex items-center gap-2">
                                <span className="text-xs font-semibold text-[var(--aurora-fg1)] font-mono">
                                  {item.date}
                                </span>
                                {isToday && (
                                  <span className="text-[9px] px-2 py-0.2 rounded-full font-bold bg-[#10B981]/20 text-[#10B981]">
                                    今日活跃
                                  </span>
                                )}
                              </div>
                              <div className="text-[11px] text-[var(--aurora-fg3)] mt-0.5 flex items-center gap-2">
                                <span>吸收会话与沉淀：<strong>{item.document_count}</strong> 篇文档</span>
                                {item.tools && item.tools.length > 0 && (
                                  <span className="text-[10px] text-[var(--aurora-fg4)] font-mono">
                                    来源: {item.tools.join(", ")}
                                  </span>
                                )}
                              </div>
                            </div>
                          </div>

                          <div className="flex items-center gap-2 shrink-0">
                            <span className="text-xs text-[var(--aurora-accent)] font-mono font-medium">
                              +{item.document_count * 20} EXP
                            </span>
                            <span className="text-[11px] text-[var(--aurora-fg4)]">⚡</span>
                          </div>
                        </div>
                      );
                    })
                  ) : (
                    <Glass padding={20} radius={16} className="text-center text-xs text-[var(--aurora-fg3)]">
                      正在同步过去 30 天每日进化成长数据...
                    </Glass>
                  )}
                </div>
              </div>
            )}

            {/* ─────────────────────────────────────────────────────────────
                CHAPTER VIEW 7: 终端守护矩阵 (Active Guardian Matrix)
                ───────────────────────────────────────────────────────────── */}
            {activeTab === "matrix" && (
              <div className="p-4 rounded-2xl border border-[var(--aurora-border)] bg-[var(--aurora-surface-solid)] shadow-xs space-y-4">
                <div>
                  <div className="flex items-center gap-2">
                    <span className="font-bold text-sm text-[var(--aurora-fg1)]">
                      全域 AI 终端配置文件热写入
                    </span>
                    <span className="text-[10px] font-medium text-[#10B981] bg-[rgba(16,185,129,0.12)] px-2 py-0.5 rounded-full">
                      5 端实时热注入
                    </span>
                  </div>
                  <p className="text-[11px] text-[var(--aurora-fg3)] mt-1 leading-relaxed">
                    画像准则通过本地守护程序实时回写至以下开发环境：
                  </p>
                </div>

                {state?.devices.map((device) => (
                  <div key={device.device_id} className="space-y-2.5">
                    <div className="flex items-center gap-2 text-xs font-semibold text-[var(--aurora-fg2)]">
                      <Icon name="devices" size={14} />
                      <span>{device.name}</span>
                      {!device.online && <Chip tone="neutral">离线</Chip>}
                      {device.status.reported_at && (
                        <span className="text-[10px] text-[var(--aurora-fg4)] font-normal ml-auto font-mono">
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
                            className={`p-3 rounded-xl border transition-all cursor-pointer flex flex-col justify-between ${
                              on
                                ? "bg-[var(--aurora-surface)] border-[var(--aurora-accent)] shadow-2xs"
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
                                  <span className="w-1.5 h-1.5 rounded-full bg-[#10B981] breathing-glow-emerald" />
                                  已注入
                                </span>
                              )}
                            </div>

                            <div className="text-[10px] text-[var(--aurora-fg3)] leading-tight mb-2">
                              {meta.desc}
                            </div>

                            <div className="pt-1.5 border-t border-[var(--aurora-border)] flex items-center justify-between text-[9px] font-mono text-[var(--aurora-fg4)]">
                              <span className="truncate max-w-[150px]">{meta.file}</span>
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
                CHAPTER VIEW 8: 避坑经验自学习 (Learned Corrections)
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
                CHAPTER VIEW 9: 底层源码比对与 Markdown 历史 (Source & Diff)
                ───────────────────────────────────────────────────────────── */}
            {activeTab === "source" && (
              <div className="space-y-3">
                {draft && (
                  <Glass padding={16} radius={18} style={{ border: "1px solid var(--aurora-accent)" }}>
                    <div className="flex items-center gap-2 mb-2">
                      <Chip tone="accent" icon="edit">{t.persona.draft}</Chip>
                      <span className="text-xs text-[var(--aurora-fg4)] font-mono">{formatTime(draft.updated_at)}</span>
                    </div>

                    {editing === "draft" ? (
                      <ProfileEditor initial={draft.content} onSave={saveDraft} onCancel={() => setEditing(null)} busy={busy !== null} />
                    ) : (
                      <>
                        {diff && published && (diff.added.length > 0 || diff.removed.length > 0) && (
                          <div className="mb-3 p-2.5 rounded-xl bg-[var(--aurora-chip)] border border-[var(--aurora-border)] text-xs font-mono">
                            <div className="font-bold text-[var(--aurora-fg1)] mb-1">变更比对 (Diff)：</div>
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
                        <div className="flex gap-2 justify-end mt-3">
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

                <Glass padding={16} radius={18}>
                  <div className="flex items-center justify-between mb-2.5">
                    <div className="flex items-center gap-2">
                      <Chip tone="success" icon="check">已发布原始规则文件 (Markdown)</Chip>
                      <span className="text-xs text-[var(--aurora-fg4)] font-mono">
                        v{published?.version} · {formatTime(published?.published_at)}
                      </span>
                    </div>
                    {!draft && editing === null && (
                      <Btn variant="ghost" size="sm" icon="edit" onClick={() => setEditing("published")}>
                        手动修改
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
                    <div className="prose prose-sm max-w-none text-xs leading-relaxed p-3.5 rounded-xl bg-[var(--aurora-surface-solid)] border border-[var(--aurora-border)]">
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
