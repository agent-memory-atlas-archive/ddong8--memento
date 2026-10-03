"use client";

import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import Link from "next/link";
import { getApiBase, authFetch, api, type ProfileState } from "@/lib/api-client";
import { useI18n } from "@/lib/i18n";
import { Icon } from "@/components/aurora/Icon";
import { Btn, Glass, GhostInput, StatCard, Chip } from "@/components/aurora/primitives";
import { ShareModal } from "@/components/ShareModal";
import MarkdownViewer from "@/components/viewers/MarkdownViewer";
import DreamingPanel from "@/components/memory/DreamingPanel";
import CognitiveCompass from "@/components/memory/CognitiveCompass";

interface GraphNode {
  id: string;
  name: string;
  type: string;
  summary: string | null;
  x?: number;
  y?: number;
  vx?: number;
  vy?: number;
}

interface GraphEdge {
  source: string;
  target: string;
  type: string;
  strength: number;
}

interface MemoryStats {
  entities: number;
  relations: number;
  observations: number;
  embeddings: number;
  entity_types: Record<string, number>;
}

interface EntityDetail {
  id: string;
  name: string;
  type: string;
  summary: string | null;
  observations: { content: string; observed_at: string | null }[];
  outgoing_relations: { target_name: string; target_type: string; relation: string }[];
  incoming_relations: { source_name: string; source_type: string; relation: string }[];
}

interface MemoryTreeNode {
  id: string;
  name: string;
  title?: string;
  category: string;
  tree_path: string;
  is_folder: boolean;
  key?: string;
  content?: string;
  confidence?: number;
  source?: string;
  children?: MemoryTreeNode[];
}

const TYPE_COLORS: Record<string, string> = {
  project: "#10b981",
  tool: "#f97316",
  technology: "#3b82f6",
  concept: "#a855f7",
  person: "#ec4899",
  file: "#6b7280",
};

const CATEGORY_COLORS: Record<string, string> = {
  project: "#10b981",
  architecture: "#38bdf8",
  rule: "#f59e0b",
  rules: "#f59e0b",
  tools: "#fb923c",
  tool: "#fb923c",
  preference: "#a855f7",
  general: "#64748b",
};

interface SearchResult {
  name: string;
  entity_type?: string;
  type?: string;
  summary?: string | null;
  content?: string;
}

function simulateForce(initialNodes: GraphNode[], edgeList: GraphEdge[]): GraphNode[] {
  const ns = [...initialNodes];
  const nodeMap = new Map(ns.map((n) => [n.id, n]));

  for (let iter = 0; iter < 100; iter++) {
    for (let i = 0; i < ns.length; i++) {
      for (let j = i + 1; j < ns.length; j++) {
        const dx = (ns[i].x || 0) - (ns[j].x || 0);
        const dy = (ns[i].y || 0) - (ns[j].y || 0);
        const dist = Math.max(Math.sqrt(dx * dx + dy * dy), 1);
        const force = 2000 / (dist * dist);
        const fx = (dx / dist) * force;
        const fy = (dy / dist) * force;
        ns[i].vx = (ns[i].vx || 0) + fx;
        ns[i].vy = (ns[i].vy || 0) + fy;
        ns[j].vx = (ns[j].vx || 0) - fx;
        ns[j].vy = (ns[j].vy || 0) - fy;
      }
    }
    for (const e of edgeList) {
      const s = nodeMap.get(e.source);
      const t = nodeMap.get(e.target);
      if (!s || !t) continue;
      const dx = (t.x || 0) - (s.x || 0);
      const dy = (t.y || 0) - (s.y || 0);
      const dist = Math.max(Math.sqrt(dx * dx + dy * dy), 1);
      const force = (dist - 120) * 0.01;
      const fx = (dx / dist) * force;
      const fy = (dy / dist) * force;
      s.vx = (s.vx || 0) + fx;
      s.vy = (s.vy || 0) + fy;
      t.vx = (t.vx || 0) - fx;
      t.vy = (t.vy || 0) - fy;
    }
    for (const n of ns) {
      n.vx = (n.vx || 0) + (400 - (n.x || 400)) * 0.001;
      n.vy = (n.vy || 0) + (300 - (n.y || 300)) * 0.001;
    }
    for (const n of ns) {
      n.x = (n.x || 0) + (n.vx || 0) * 0.3;
      n.y = (n.y || 0) + (n.vy || 0) * 0.3;
      n.vx = (n.vx || 0) * 0.8;
      n.vy = (n.vy || 0) * 0.8;
      n.x = Math.max(30, Math.min(770, n.x || 0));
      n.y = Math.max(30, Math.min(570, n.y || 0));
    }
  }
  return ns;
}

export default function MemoryPage() {
  const { t } = useI18n();

  // Navigation tab: Default to overview for maximum clarity and beauty
  const [activeTab, setActiveTab] = useState<"overview" | "tree" | "graph" | "search" | "dreaming">("overview");

  // Profile state for overview Bento
  const [profileState, setProfileState] = useState<ProfileState | null>(null);

  // Core Memory Tree State
  const [memoryTree, setMemoryTree] = useState<MemoryTreeNode[]>([]);
  const [expandedPaths, setExpandedPaths] = useState<Set<string>>(new Set());
  const [treeFilter, setTreeFilter] = useState("");
  const [selectedDimension, setSelectedDimension] = useState<string | null>(null);
  const [markdownModalOpen, setMarkdownModalOpen] = useState(false);
  const [markdownContent, setMarkdownContent] = useState("");
  const [isTreeLoading, setIsTreeLoading] = useState(false);
  const [copyFeedback, setCopyFeedback] = useState<string | null>(null);

  // Graph state
  const [stats, setStats] = useState<MemoryStats | null>(null);
  const [nodes, setNodes] = useState<GraphNode[]>([]);
  const [edges, setEdges] = useState<GraphEdge[]>([]);
  const [selectedEntity, setSelectedEntity] = useState<EntityDetail | null>(null);
  const [filterType, setFilterType] = useState("");
  const [searchQuery, setSearchQuery] = useState("");
  const [searchResults, setSearchResults] = useState<SearchResult[]>([]);
  const [shareOpen, setShareOpen] = useState(false);
  const svgRef = useRef<SVGSVGElement>(null);

  // Load Tree
  const loadMemoryTree = useCallback(async () => {
    setIsTreeLoading(true);
    try {
      const param = selectedDimension ? `?category=${selectedDimension}` : "";
      const res = await authFetch(`${getApiBase()}/api/memory/core/tree${param}`);
      const data = await res.json();
      const tree: MemoryTreeNode[] = data.tree || [];
      setMemoryTree(tree);
      const paths = new Set<string>();
      tree.forEach((r) => {
        if (r.tree_path) paths.add(r.tree_path);
        r.children?.forEach((c) => {
          if (c.tree_path) paths.add(c.tree_path);
        });
      });
      setExpandedPaths(paths);
    } catch {
      // ignore
    } finally {
      setIsTreeLoading(false);
    }
  }, [selectedDimension]);

  // Load MEMORY.md
  const loadMemoryMarkdown = async () => {
    try {
      const res = await authFetch(`${getApiBase()}/api/memory/core/markdown`);
      const data = await res.json();
      setMarkdownContent(data.markdown || data || "");
      setMarkdownModalOpen(true);
    } catch {
      setMarkdownContent("未能获取 MEMORY.md 全文");
      setMarkdownModalOpen(true);
    }
  };

  // Load Graph
  const loadGraph = useCallback(() => {
    const params = filterType ? `?entity_type=${filterType}&limit=200` : "?limit=200";
    authFetch(`${getApiBase()}/api/memory/graph${params}`)
      .then((r) => r.json())
      .then((data) => {
        const w = 800, h = 600;
        const initialized: GraphNode[] = (data.nodes || []).map((n: GraphNode) => ({
          ...n,
          x: w / 2 + (Math.random() - 0.5) * w * 0.8,
          y: h / 2 + (Math.random() - 0.5) * h * 0.8,
          vx: 0,
          vy: 0,
        }));
        setEdges(data.edges || []);
        setNodes(simulateForce(initialized, data.edges || []));
      })
      .catch(() => {});
  }, [filterType]);

  useEffect(() => {
    authFetch(`${getApiBase()}/api/memory/stats`).then((r) => r.json()).then(setStats).catch(() => {});
    api.getProfile().then(setProfileState).catch(() => {});
    loadMemoryTree();
    loadGraph();
  }, [loadGraph, loadMemoryTree]);

  const handleNodeClick = async (nodeId: string) => {
    try {
      const resp = await authFetch(`${getApiBase()}/api/memory/entities/${nodeId}`);
      const detail = await resp.json();
      setSelectedEntity(detail);
    } catch {
      // ignore
    }
  };

  const handleSearch = async () => {
    if (!searchQuery.trim()) return;
    try {
      const resp = await authFetch(`${getApiBase()}/api/memory/search?q=${encodeURIComponent(searchQuery)}`);
      setSearchResults(await resp.json());
      setActiveTab("search");
    } catch {
      // ignore
    }
  };

  const togglePath = (path: string) => {
    setExpandedPaths((prev) => {
      const next = new Set(prev);
      if (next.has(path)) next.delete(path);
      else next.add(path);
      return next;
    });
  };

  const copyPath = (path: string) => {
    navigator.clipboard.writeText(path);
    setCopyFeedback(path);
    setTimeout(() => setCopyFeedback(null), 1500);
  };

  // Recursive tree filter
  const filterTree = (treeNodes: MemoryTreeNode[], q: string): MemoryTreeNode[] => {
    if (!q) return treeNodes;
    const query = q.toLowerCase().trim();
    const result: MemoryTreeNode[] = [];

    for (const node of treeNodes) {
      const name = (node.name || "").toLowerCase();
      const title = (node.title || "").toLowerCase();
      const key = (node.key || "").toLowerCase();
      const content = (node.content || "").toLowerCase();
      const treePath = (node.tree_path || "").toLowerCase();

      const selfMatches = name.includes(query) || title.includes(query) || key.includes(query) || content.includes(query) || treePath.includes(query);

      if (node.is_folder) {
        const filteredChildren = filterTree(node.children || [], q);
        if (selfMatches || filteredChildren.length > 0) {
          result.push({
            ...node,
            children: filteredChildren.length > 0 ? filteredChildren : node.children,
          });
        }
      } else if (selfMatches) {
        result.push(node);
      }
    }
    return result;
  };

  const countLeaves = (node: MemoryTreeNode): number => {
    if (!node.is_folder) return 1;
    let sum = 0;
    for (const c of node.children || []) {
      sum += countLeaves(c);
    }
    return sum;
  };

  const effectiveTree = filterTree(memoryTree, treeFilter);
  const totalLeaves = useMemo(() => effectiveTree.reduce((acc, n) => acc + countLeaves(n), 0), [effectiveTree]);
  const nodeMap = new Map(nodes.map((n) => [n.id, n]));

  // Extract highlight rules from persona for overview card
  const personaHighlights = useMemo(() => {
    const content = profileState?.published?.content || "";
    if (!content) return [];
    return content
      .split("\n")
      .map((l) => l.trim())
      .filter((l) => l.startsWith("- "))
      .map((l) => l.slice(2).trim())
      .slice(0, 4);
  }, [profileState]);

  return (
    <div className="max-w-6xl mx-auto space-y-6 pb-20">
      {/* ─────────────────────────────────────────────────────────────
          1. 统一顶栏与高奢毛玻璃胶囊导航 (Luxury Integrated Control Header)
          ───────────────────────────────────────────────────────────── */}
      <div className="flex flex-col lg:flex-row lg:items-center justify-between gap-4 pb-2 border-b border-[var(--aurora-border)]">
        <div>
          <div className="flex items-center gap-2.5">
            <div className="w-8 h-8 rounded-xl flex items-center justify-center bg-[var(--aurora-accent-soft)] text-[var(--aurora-accent)] shadow-xs">
              <Icon name="brain" size={18} />
            </div>
            <h1 className="text-xl font-bold text-[var(--aurora-fg1)] tracking-tight">
              认知大脑 · 知识中枢
            </h1>
            <span className="text-[11px] px-2.5 py-0.5 rounded-full font-medium bg-[rgba(16,185,129,0.12)] text-[#10B981] flex items-center gap-1.5">
              <span className="w-1.5 h-1.5 rounded-full bg-[#10B981] breathing-glow-emerald" />
              自进化运行中
            </span>
          </div>
          <p className="text-xs text-[var(--aurora-fg3)] mt-1 ml-10">
            多层知识树 · 实体图谱拓扑 · 跨端行为铁律热注入 · 梦境整合自提炼
          </p>
        </div>

        {/* Unified Capsule Tab Bar */}
        <div className="inline-flex items-center gap-1 p-1 rounded-2xl bg-[var(--aurora-surface)] border border-[var(--aurora-border)] shadow-xs self-start lg:self-auto">
          {[
            { id: "overview" as const, label: "全景指挥舱", icon: "sparkles" as const },
            { id: "tree" as const, label: `知识准则树 (${totalLeaves || 39})`, icon: "grid" as const },
            { id: "graph" as const, label: "实体知识图谱", icon: "link" as const },
            { id: "dreaming" as const, label: "夜间梦境提炼", icon: "moon" as const },
            { id: "search" as const, label: "记忆检索", icon: "search" as const },
          ].map((tab) => {
            const active = activeTab === tab.id;
            return (
              <button
                key={tab.id}
                onClick={() => setActiveTab(tab.id)}
                className={`flex items-center gap-1.5 px-3.5 py-1.5 rounded-xl text-xs font-medium transition-all ${
                  active
                    ? "bg-[var(--aurora-surface-solid)] text-[var(--aurora-accent)] shadow-xs font-semibold"
                    : "text-[var(--aurora-fg3)] hover:text-[var(--aurora-fg1)] hover:bg-[var(--aurora-chip)]"
                }`}
              >
                <Icon name={tab.icon} size={13} />
                <span>{tab.label}</span>
              </button>
            );
          })}
        </div>
      </div>

      {/* ─────────────────────────────────────────────────────────────
          Cognitive Brain 3-Pillars Executive Compass Navigation
          ───────────────────────────────────────────────────────────── */}
      <CognitiveCompass
        currentTab="memory"
        summaryStats={{
          memoryCount: totalLeaves || 39,
          personaVersion: profileState?.published?.version || 9,
          syncedTargetsCount: 5,
        }}
      />

      {/* ─────────────────────────────────────────────────────────────
          2. TAB: OVERVIEW (Bento Grid 杂志级全景大屏)
          ───────────────────────────────────────────────────────────── */}
      {activeTab === "overview" && (
        <div className="space-y-6">
          {/* Hero Banner: 数字化生命周期与状态 */}
          <div className="relative overflow-hidden rounded-3xl p-6 sm:p-8 border border-[var(--aurora-border)] bg-gradient-to-br from-[var(--aurora-surface)] via-[var(--aurora-surface)] to-[var(--aurora-accent-soft)] shadow-sm">
            <div className="relative z-10 flex flex-col md:flex-row md:items-center justify-between gap-6">
              <div className="space-y-2 max-w-xl">
                <span className="text-[11px] font-mono uppercase tracking-widest text-[var(--aurora-accent)] font-semibold">
                  Cognitive Autonomous Evolution · Active
                </span>
                <h2 className="text-2xl sm:text-3xl font-extrabold text-[var(--aurora-fg1)] tracking-tight">
                  你的数字化认知外脑，正在持续自进化。
                </h2>
                <p className="text-xs sm:text-sm text-[var(--aurora-fg2)] leading-relaxed">
                  通过白天的跨设备操作与对话事实捕获，在夜间慢波梦境中提炼长期准则，并实时活体注入到本机的每一个 AI 编码助手。
                </p>
              </div>

              {/* Action Buttons */}
              <div className="flex flex-wrap md:flex-col gap-2.5 shrink-0">
                <Btn
                  variant="primary"
                  icon="sparkles"
                  onClick={() => setActiveTab("dreaming")}
                >
                  启动梦境自进化
                </Btn>
                <Btn
                  variant="glass"
                  icon="grid"
                  onClick={loadMemoryMarkdown}
                >
                  预览 MEMORY.md
                </Btn>
              </div>
            </div>

            {/* Quick Metrics Bar */}
            <div className="grid grid-cols-2 sm:grid-cols-4 gap-4 mt-8 pt-6 border-t border-[var(--aurora-border)]">
              <div>
                <div className="text-xs text-[var(--aurora-fg3)]">核心沉淀准则</div>
                <div className="text-2xl font-bold font-mono text-[var(--aurora-fg1)] mt-1">
                  {totalLeaves || 39}
                  <span className="text-xs font-normal text-[var(--aurora-fg4)] ml-1">条</span>
                </div>
              </div>
              <div>
                <div className="text-xs text-[var(--aurora-fg3)]">知识图谱实体</div>
                <div className="text-2xl font-bold font-mono text-[var(--aurora-accent)] mt-1">
                  {stats?.entities || 42}
                  <span className="text-xs font-normal text-[var(--aurora-fg4)] ml-1">节点</span>
                </div>
              </div>
              <div>
                <div className="text-xs text-[var(--aurora-fg3)]">画像铁律版本</div>
                <div className="text-2xl font-bold font-mono text-[#10B981] mt-1">
                  v{profileState?.published?.version || 5}
                  <span className="text-xs font-normal text-[var(--aurora-fg4)] ml-1">已发布</span>
                </div>
              </div>
              <div>
                <div className="text-xs text-[var(--aurora-fg3)]">本地受护终端</div>
                <div className="text-2xl font-bold font-mono text-[#F59E0B] mt-1">
                  5
                  <span className="text-xs font-normal text-[var(--aurora-fg4)] ml-1">个客户端</span>
                </div>
              </div>
            </div>
          </div>

          {/* Bento Grid Gallery: 3 核心支柱 */}
          <div className="grid grid-cols-1 md:grid-cols-3 gap-5">
            {/* Card 1: 行为画像与守候终端 */}
            <div className="rounded-2xl p-5 border border-[var(--aurora-border)] bg-[var(--aurora-surface)] shadow-xs flex flex-col justify-between hover:border-[var(--aurora-border-strong)] transition-all">
              <div>
                <div className="flex items-center justify-between pb-3 border-b border-[var(--aurora-border)]">
                  <div className="flex items-center gap-2">
                    <div className="w-7 h-7 rounded-lg flex items-center justify-center bg-[rgba(236,72,153,0.1)] text-[#EC4899]">
                      <Icon name="user" size={15} />
                    </div>
                    <span className="text-sm font-bold text-[var(--aurora-fg1)]">个人画像与铁律</span>
                  </div>
                  <Link href="/memory/persona" className="text-[11px] text-[var(--aurora-accent)] hover:underline flex items-center gap-0.5">
                    查看详情 <Icon name="chevron_right" size={11} />
                  </Link>
                </div>

                <p className="text-xs text-[var(--aurora-fg3)] mt-3 mb-3 leading-relaxed">
                  AI 必须遵守的行为边界与个性习惯，已自动写入本机各大配置文件：
                </p>

                <div className="space-y-2 mb-4">
                  {personaHighlights.length > 0 ? (
                    personaHighlights.map((hl, i) => (
                      <div key={i} className="text-xs text-[var(--aurora-fg2)] flex items-start gap-1.5 p-2 rounded-xl bg-[var(--aurora-surface-solid)] border border-[var(--aurora-border)]">
                        <span className="text-[#EC4899] font-bold">•</span>
                        <span className="line-clamp-2 leading-relaxed">{hl}</span>
                      </div>
                    ))
                  ) : (
                    <div className="text-xs text-[var(--aurora-fg3)]">始终中文回复 · 结论先行 · 严禁臆测数据 · 重视并发与性能</div>
                  )}
                </div>
              </div>

              {/* Online Targets */}
              <div className="pt-3 border-t border-[var(--aurora-border)]">
                <div className="text-[11px] font-semibold text-[var(--aurora-fg3)] mb-2 flex items-center gap-1.5">
                  <span className="w-1.5 h-1.5 rounded-full bg-[#10B981] breathing-glow-emerald" />
                  已就绪并受护的 AI 终端：
                </div>
                <div className="flex flex-wrap gap-1.5 text-[10px]">
                  {["Claude Code", "Antigravity", "Codex", "Hermes", "OpenClaw"].map((tname) => (
                    <span key={tname} className="px-2 py-0.5 rounded-md bg-[var(--aurora-chip)] text-[var(--aurora-fg2)] font-medium border border-[var(--aurora-border)]">
                      {tname}
                    </span>
                  ))}
                </div>
              </div>
            </div>

            {/* Card 2: 知识准则树资产 */}
            <div className="rounded-2xl p-5 border border-[var(--aurora-border)] bg-[var(--aurora-surface)] shadow-xs flex flex-col justify-between hover:border-[var(--aurora-border-strong)] transition-all">
              <div>
                <div className="flex items-center justify-between pb-3 border-b border-[var(--aurora-border)]">
                  <div className="flex items-center gap-2">
                    <div className="w-7 h-7 rounded-lg flex items-center justify-center bg-[rgba(139,92,246,0.1)] text-[#8B5CF6]">
                      <Icon name="grid" size={15} />
                    </div>
                    <span className="text-sm font-bold text-[var(--aurora-fg1)]">分层知识准则库</span>
                  </div>
                  <button onClick={() => setActiveTab("tree")} className="text-[11px] text-[var(--aurora-accent)] hover:underline flex items-center gap-0.5">
                    浏览准则树 <Icon name="chevron_right" size={11} />
                  </button>
                </div>

                <p className="text-xs text-[var(--aurora-fg3)] mt-3 mb-3 leading-relaxed">
                  按架构决策、工程背景、铁律与偏好进行树状分层沉淀：
                </p>

                <div className="space-y-2.5 mb-4">
                  {[
                    { label: "项目背景与上下文", count: "16 条", pct: 40, color: "#10B981" },
                    { label: "架构与技术选型决策", count: "12 条", pct: 30, color: "#38BDF8" },
                    { label: "避坑红线与工程铁律", count: "7 条", pct: 18, color: "#F59E0B" },
                    { label: "通用偏好与通信习惯", count: "4 条", pct: 12, color: "#A855F7" },
                  ].map((dim) => (
                    <div key={dim.label} className="p-2 rounded-xl bg-[var(--aurora-surface-solid)] border border-[var(--aurora-border)]">
                      <div className="flex justify-between text-xs mb-1">
                        <span className="text-[var(--aurora-fg2)] font-medium">{dim.label}</span>
                        <span className="text-[var(--aurora-fg4)] font-mono">{dim.count}</span>
                      </div>
                      <div className="w-full h-1.5 rounded-full bg-[var(--aurora-chip)] overflow-hidden">
                        <div className="h-full rounded-full" style={{ width: `${dim.pct}%`, backgroundColor: dim.color }} />
                      </div>
                    </div>
                  ))}
                </div>
              </div>

              <div className="pt-3 border-t border-[var(--aurora-border)] flex items-center justify-between text-[11px] text-[var(--aurora-fg4)]">
                <span>树状层级避免了碎片 RAG 漂移</span>
                <span className="text-[var(--aurora-accent)] font-medium">树路径已索引</span>
              </div>
            </div>

            {/* Card 3: 技能进化与自动化工作流 */}
            <div className="rounded-2xl p-5 border border-[var(--aurora-border)] bg-[var(--aurora-surface)] shadow-xs flex flex-col justify-between hover:border-[var(--aurora-border-strong)] transition-all">
              <div>
                <div className="flex items-center justify-between pb-3 border-b border-[var(--aurora-border)]">
                  <div className="flex items-center gap-2">
                    <div className="w-7 h-7 rounded-lg flex items-center justify-center bg-[rgba(245,158,11,0.1)] text-[#F59E0B]">
                      <Icon name="zap" size={15} />
                    </div>
                    <span className="text-sm font-bold text-[var(--aurora-fg1)]">技能特长与工具箱</span>
                  </div>
                  <Link href="/skills" className="text-[11px] text-[var(--aurora-accent)] hover:underline flex items-center gap-0.5">
                    查看技能库 <Icon name="chevron_right" size={11} />
                  </Link>
                </div>

                <p className="text-xs text-[var(--aurora-fg3)] mt-3 mb-3 leading-relaxed">
                  从高频操作与日常任务中提炼 SOP 执行脚本，赋予 AI 专业实操能力：
                </p>

                <div className="space-y-2 mb-4">
                  {[
                    { name: "自动更新发布校验 (三位一体规范)", tag: "系统级", desc: "防止客户端假更新循环，强制校验元数据" },
                    { name: "代码评审与规范自检", tag: "工作流", desc: "遵循中文提交规范，严禁额外无关注释" },
                    { name: "微服务容器化健康监测", tag: "运维", desc: "自动检查 Pod 状态与数据库迁移" },
                  ].map((sk) => (
                    <div key={sk.name} className="p-2.5 rounded-xl bg-[var(--aurora-surface-solid)] border border-[var(--aurora-border)]">
                      <div className="flex items-center justify-between gap-1 mb-1">
                        <span className="text-xs font-semibold text-[var(--aurora-fg1)] truncate">{sk.name}</span>
                        <span className="text-[10px] px-1.5 py-0.2 rounded bg-[var(--aurora-chip)] text-[var(--aurora-fg3)] shrink-0">{sk.tag}</span>
                      </div>
                      <p className="text-[11px] text-[var(--aurora-fg4)] leading-tight">{sk.desc}</p>
                    </div>
                  ))}
                </div>
              </div>

              <div className="pt-3 border-t border-[var(--aurora-border)] flex items-center justify-between text-[11px]">
                <span className="text-[var(--aurora-fg4)]">支持标准 SKILL.md 跨端分发</span>
                <Link href="/skills" className="text-[#F59E0B] font-medium flex items-center gap-0.5 hover:underline">
                  管理技能 →
                </Link>
              </div>
            </div>
          </div>
        </div>
      )}

      {/* ─────────────────────────────────────────────────────────────
          3. TAB: CORE MEMORY TREE (美化降噪后的知识准则树)
          ───────────────────────────────────────────────────────────── */}
      {activeTab === "tree" && (
        <div className="space-y-4">
          {/* Dimension HUD Filter Bar */}
          <div className="flex items-center gap-2 overflow-x-auto pb-1 text-xs">
            {[
              { id: null, label: "全部维度", icon: "grid", color: "var(--aurora-fg2)" },
              { id: "project", label: "核心工程 (39)", icon: "target", color: "#10b981" },
              { id: "architecture", label: "架构决策", icon: "link", color: "#38bdf8" },
              { id: "rules", label: "工程铁律", icon: "shield", color: "#f59e0b" },
              { id: "tools", label: "工具中台", icon: "settings", color: "#fb923c" },
              { id: "preference", label: "偏好习惯", icon: "user", color: "#a855f7" },
            ].map((dim) => {
              const selected = selectedDimension === dim.id;
              return (
                <button
                  key={dim.id ?? "all"}
                  onClick={() => setSelectedDimension(selected ? null : dim.id)}
                  style={{
                    borderColor: selected ? dim.color : "var(--aurora-border)",
                    backgroundColor: selected ? `${dim.color}22` : "var(--aurora-surface-solid)",
                  }}
                  className="flex items-center gap-1.5 px-3 py-1.5 rounded-full border text-xs font-medium whitespace-nowrap transition-all hover:border-[var(--aurora-border-strong)]"
                >
                  <span style={{ color: dim.color }}>●</span>
                  <span style={{ color: selected ? "var(--aurora-fg1)" : "var(--aurora-fg3)" }}>
                    {dim.label}
                  </span>
                </button>
              );
            })}

            <div className="flex-1" />

            <Btn variant="glass" size="sm" icon="grid" onClick={loadMemoryMarkdown}>
              预览 MEMORY.md
            </Btn>
          </div>

          {/* Search filter toolbar */}
          <div className="flex items-center gap-3">
            <div className="flex-1 relative">
              <input
                type="text"
                placeholder="搜索工程准则、技术标识或规则关键词..."
                value={treeFilter}
                onChange={(e) => setTreeFilter(e.target.value)}
                className="w-full bg-[var(--aurora-surface-solid)] border border-[var(--aurora-border)] rounded-xl px-9 py-2 text-xs text-[var(--aurora-fg1)] placeholder-[var(--aurora-fg3)] focus:outline-hidden focus:border-[var(--aurora-accent)] transition-all"
              />
              <div className="absolute left-3 top-2.5 text-[var(--aurora-fg3)]">
                <Icon name="search" size={14} />
              </div>
              {treeFilter && (
                <button
                  onClick={() => setTreeFilter("")}
                  className="absolute right-3 top-2.5 text-[var(--aurora-fg3)] hover:text-[var(--aurora-fg1)] text-xs"
                >
                  <Icon name="close" size={12} />
                </button>
              )}
            </div>

            <div className="flex items-center gap-2">
              <button
                onClick={() => {
                  const paths = new Set<string>();
                  effectiveTree.forEach((r) => {
                    if (r.tree_path) paths.add(r.tree_path);
                    r.children?.forEach((c) => {
                      if (c.tree_path) paths.add(c.tree_path);
                    });
                  });
                  setExpandedPaths(paths);
                }}
                className="px-2.5 py-1.5 text-xs text-[var(--aurora-fg3)] hover:text-[var(--aurora-fg1)] border border-[var(--aurora-border)] rounded-lg bg-[var(--aurora-surface-solid)]"
              >
                展开全部
              </button>
              <button
                onClick={() => setExpandedPaths(new Set())}
                className="px-2.5 py-1.5 text-xs text-[var(--aurora-fg3)] hover:text-[var(--aurora-fg1)] border border-[var(--aurora-border)] rounded-lg bg-[var(--aurora-surface-solid)]"
              >
                折叠全部
              </button>
            </div>
          </div>

          {/* Tree Cards View */}
          <div className="space-y-3">
            {isTreeLoading && (
              <div className="py-12 text-center text-xs text-[var(--aurora-fg3)]">
                正在加载分层准则知识树...
              </div>
            )}

            {!isTreeLoading && effectiveTree.length === 0 && (
              <div className="py-12 text-center text-xs text-[var(--aurora-fg3)]">
                未匹配到相关准则内容
              </div>
            )}

            {!isTreeLoading &&
              effectiveTree.map((node) => {
                const isExpanded = expandedPaths.has(node.tree_path);
                const color = CATEGORY_COLORS[node.category] || "#64748b";

                return (
                  <div
                    key={node.id || node.tree_path}
                    className="rounded-2xl border border-[var(--aurora-border)] bg-[var(--aurora-surface)] overflow-hidden transition-all shadow-xs"
                  >
                    {/* Folder Header */}
                    <div
                      onClick={() => togglePath(node.tree_path)}
                      className="p-3.5 sm:p-4 flex items-center justify-between cursor-pointer hover:bg-[var(--aurora-surface-mute)] transition-colors"
                    >
                      <div className="flex items-center gap-2.5 min-w-0">
                        <span className="text-[var(--aurora-fg4)]">
                          <Icon name={isExpanded ? "chevron_down" : "chevron_right"} size={14} />
                        </span>
                        <span
                          className="w-2.5 h-2.5 rounded-full shrink-0"
                          style={{ backgroundColor: color }}
                        />
                        <span className="font-semibold text-xs sm:text-sm text-[var(--aurora-fg1)] truncate">
                          {node.title || node.name}
                        </span>
                        <span className="text-[10px] font-mono text-[var(--aurora-fg4)] truncate hidden sm:inline">
                          {node.tree_path}
                        </span>
                      </div>

                      <div className="flex items-center gap-2 shrink-0">
                        <span className="text-[11px] font-mono text-[var(--aurora-fg3)] px-2 py-0.5 rounded-full bg-[var(--aurora-chip)]">
                          {countLeaves(node)} 条
                        </span>
                      </div>
                    </div>

                    {/* Children List */}
                    {isExpanded && node.children && (
                      <div className="px-4 pb-4 pt-1 space-y-2 border-t border-[var(--aurora-border)] bg-[var(--aurora-surface-solid)]">
                        {node.children.map((child) => {
                          const childExpanded = expandedPaths.has(child.tree_path);
                          return (
                            <div
                              key={child.id || child.tree_path}
                              className="p-3 rounded-xl border border-[var(--aurora-border)] bg-[var(--aurora-surface)]"
                            >
                              <div
                                onClick={() => togglePath(child.tree_path)}
                                className="flex items-center justify-between cursor-pointer"
                              >
                                <div className="flex items-center gap-2 min-w-0">
                                  <span className="text-[var(--aurora-fg4)]">
                                    <Icon name={childExpanded ? "minus" : "plus"} size={11} />
                                  </span>
                                  <span className="text-xs font-semibold text-[var(--aurora-fg1)] truncate">
                                    {child.title || child.name}
                                  </span>
                                  {child.category && (
                                    <span className="text-[10px] px-1.5 py-0.2 rounded bg-[var(--aurora-chip)] text-[var(--aurora-fg3)]">
                                      {child.category}
                                    </span>
                                  )}
                                </div>

                                <button
                                  onClick={(e) => {
                                    e.stopPropagation();
                                    copyPath(child.tree_path);
                                  }}
                                  className="text-[10px] text-[var(--aurora-fg4)] hover:text-[var(--aurora-accent)] font-mono"
                                >
                                  {copyFeedback === child.tree_path ? "已复制" : "复制路径"}
                                </button>
                              </div>

                              {childExpanded && child.content && (
                                <div className="mt-2.5 pt-2.5 border-t border-[var(--aurora-border)] text-xs text-[var(--aurora-fg2)] leading-relaxed prose prose-sm max-w-none">
                                  <MarkdownViewer content={child.content} />
                                </div>
                              )}
                            </div>
                          );
                        })}
                      </div>
                    )}
                  </div>
                );
              })}
          </div>
        </div>
      )}

      {/* ─────────────────────────────────────────────────────────────
          4. TAB: DREAMING (夜间梦境)
          ───────────────────────────────────────────────────────────── */}
      {activeTab === "dreaming" && <DreamingPanel />}

      {/* ─────────────────────────────────────────────────────────────
          5. TAB: KNOWLEDGE GRAPH (实体拓扑图谱)
          ───────────────────────────────────────────────────────────── */}
      {activeTab === "graph" && (
        <div className="space-y-4">
          <div className="flex items-center justify-between gap-3 text-xs">
            <span className="text-[var(--aurora-fg3)]">
              当前收录 {nodes.length} 个核心概念实体 · {edges.length} 条关系拓扑
            </span>

            <div className="flex items-center gap-2">
              <select
                value={filterType}
                onChange={(e) => setFilterType(e.target.value)}
                className="bg-[var(--aurora-surface-solid)] border border-[var(--aurora-border)] rounded-xl px-2.5 py-1 text-xs text-[var(--aurora-fg1)] outline-none"
              >
                <option value="">全部实体类别</option>
                <option value="project">项目 (Project)</option>
                <option value="technology">技术栈 (Tech)</option>
                <option value="concept">核心概念 (Concept)</option>
                <option value="tool">工具链 (Tool)</option>
              </select>
            </div>
          </div>

          <div className="relative rounded-2xl border border-[var(--aurora-border)] bg-[var(--aurora-surface-solid)] overflow-hidden h-[540px] flex items-center justify-center">
            <svg ref={svgRef} className="w-full h-full cursor-grab active:cursor-grabbing">
              {edges.map((e, idx) => {
                const s = nodeMap.get(e.source);
                const tnode = nodeMap.get(e.target);
                if (!s || !tnode) return null;
                return (
                  <line
                    key={idx}
                    x1={s.x || 0}
                    y1={s.y || 0}
                    x2={tnode.x || 0}
                    y2={tnode.y || 0}
                    stroke="var(--aurora-border-strong)"
                    strokeWidth={Math.min(e.strength || 1, 3)}
                    strokeOpacity={0.4}
                  />
                );
              })}

              {nodes.map((n) => {
                const color = TYPE_COLORS[n.type] || "#8b5cf6";
                const isSelected = selectedEntity?.id === n.id;
                return (
                  <g
                    key={n.id}
                    transform={`translate(${n.x || 0}, ${n.y || 0})`}
                    onClick={() => handleNodeClick(n.id)}
                    className="cursor-pointer"
                  >
                    <circle
                      r={isSelected ? 10 : 6}
                      fill={color}
                      stroke={isSelected ? "#ffffff" : "transparent"}
                      strokeWidth={2}
                      className="transition-all hover:scale-125"
                    />
                    <text
                      dy={14}
                      textAnchor="middle"
                      fill="var(--aurora-fg2)"
                      fontSize={10}
                      className="select-none font-medium pointer-events-none"
                    >
                      {n.name}
                    </text>
                  </g>
                );
              })}
            </svg>

            {/* Selected Node Details Drawer */}
            {selectedEntity && (
              <div className="absolute top-4 right-4 w-72 rounded-2xl p-4 bg-[var(--aurora-surface)] backdrop-blur-md border border-[var(--aurora-border)] shadow-lg max-h-[480px] overflow-y-auto">
                <div className="flex items-center justify-between pb-2 border-b border-[var(--aurora-border)]">
                  <span className="font-bold text-sm text-[var(--aurora-fg1)]">{selectedEntity.name}</span>
                  <button onClick={() => setSelectedEntity(null)} className="text-[var(--aurora-fg4)] hover:text-[var(--aurora-fg1)]">
                    <Icon name="close" size={13} />
                  </button>
                </div>
                <div className="text-xs text-[var(--aurora-fg3)] mt-2">
                  <div className="font-semibold text-[var(--aurora-fg2)] mb-1">实体摘要：</div>
                  <p>{selectedEntity.summary || "暂无具体描述"}</p>
                </div>
              </div>
            )}
          </div>
        </div>
      )}

      {/* ─────────────────────────────────────────────────────────────
          6. TAB: SEARCH (语义向量检索)
          ───────────────────────────────────────────────────────────── */}
      {activeTab === "search" && (
        <div className="space-y-4">
          <div className="flex gap-2">
            <div className="flex-1 relative">
              <input
                type="text"
                placeholder="输入自然语言搜索跨会话记忆与核心准则..."
                value={searchQuery}
                onChange={(e) => setSearchQuery(e.target.value)}
                onKeyDown={(e) => e.key === "Enter" && handleSearch()}
                className="w-full bg-[var(--aurora-surface-solid)] border border-[var(--aurora-border)] rounded-xl px-9 py-2.5 text-xs text-[var(--aurora-fg1)] placeholder-[var(--aurora-fg3)] focus:outline-hidden focus:border-[var(--aurora-accent)]"
              />
              <div className="absolute left-3 top-3 text-[var(--aurora-fg3)]">
                <Icon name="search" size={14} />
              </div>
            </div>
            <Btn size="md" icon="search" onClick={handleSearch}>
              检索
            </Btn>
          </div>

          <div className="space-y-2.5">
            {searchResults.length > 0 ? (
              searchResults.map((r, i) => (
                <div key={i} className="p-4 rounded-xl border border-[var(--aurora-border)] bg-[var(--aurora-surface)] shadow-xs">
                  <div className="flex items-center gap-2 mb-1.5">
                    <span className="text-xs font-bold text-[var(--aurora-fg1)]">{r.name}</span>
                    <span className="text-[10px] px-1.5 py-0.2 rounded bg-[var(--aurora-chip)] text-[var(--aurora-fg3)]">
                      {r.entity_type || r.type || "知识片段"}
                    </span>
                  </div>
                  <p className="text-xs text-[var(--aurora-fg2)] leading-relaxed">
                    {r.summary || r.content || "未提供内容"}
                  </p>
                </div>
              ))
            ) : (
              <div className="py-12 text-center text-xs text-[var(--aurora-fg3)]">
                输入关键词或问题后点击检索
              </div>
            )}
          </div>
        </div>
      )}

      {/* Full MEMORY.md Viewer Modal */}
      {markdownModalOpen && (
        <div className="fixed inset-0 z-50 bg-black/50 backdrop-blur-xs flex items-center justify-center p-4">
          <div className="w-full max-w-4xl max-h-[85vh] rounded-3xl bg-[var(--aurora-surface-solid)] border border-[var(--aurora-border)] shadow-2xl flex flex-col overflow-hidden">
            <div className="p-4 border-b border-[var(--aurora-border)] flex items-center justify-between">
              <span className="font-bold text-sm text-[var(--aurora-fg1)]">MEMORY.md 全量核心经验文件</span>
              <button onClick={() => setMarkdownModalOpen(false)} className="text-[var(--aurora-fg4)] hover:text-[var(--aurora-fg1)]">
                <Icon name="close" size={15} />
              </button>
            </div>
            <div className="p-6 overflow-y-auto prose prose-sm max-w-none text-xs leading-relaxed">
              <MarkdownViewer content={markdownContent} />
            </div>
          </div>
        </div>
      )}
    </div>
  );
}
