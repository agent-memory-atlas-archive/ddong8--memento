"use client";

import { useCallback, useEffect, useRef, useState } from "react";
import { getApiBase, authFetch } from "@/lib/api-client";
import { useI18n } from "@/lib/i18n";
import { Icon } from "@/components/aurora/Icon";
import { Btn, Glass, GhostInput, StatCard, TopBar } from "@/components/aurora/primitives";
import { ShareModal } from "@/components/ShareModal";
import MarkdownViewer from "@/components/viewers/MarkdownViewer";

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

  // Navigation tab
  const [activeTab, setActiveTab] = useState<"tree" | "graph" | "search">("tree");

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
      // Auto expand root paths
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
  const filterTree = (nodes: MemoryTreeNode[], q: string): MemoryTreeNode[] => {
    if (!q) return nodes;
    const query = q.toLowerCase().trim();
    const result: MemoryTreeNode[] = [];

    for (const node of nodes) {
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
  const nodeMap = new Map(nodes.map((n) => [n.id, n]));

  return (
    <div className="max-w-6xl mx-auto space-y-4 sm:space-y-6">
      {/* Top Header */}
      <div className="flex flex-col sm:flex-row sm:items-center justify-between gap-3">
        <TopBar
          title={t.nav.memory || "外脑认知记忆库"}
          subtitle="三层认知架构 · 39 个核心工程 · 长期开发准则"
        />

        {/* Segmented Control Capsule Tab */}
        <div className="flex items-center gap-1.5 p-1 rounded-2xl bg-[var(--aurora-surface)] border border-[var(--aurora-border)] self-start sm:self-auto">
          <button
            onClick={() => setActiveTab("tree")}
            className={`flex items-center gap-1.5 px-3.5 py-1.5 rounded-xl text-xs font-semibold transition-all ${
              activeTab === "tree"
                ? "bg-[var(--aurora-accent)] text-black shadow-xs"
                : "text-[var(--aurora-fg3)] hover:text-[var(--aurora-fg1)]"
            }`}
          >
            <Icon name="grid" size={13} />
            <span>核心准则树 (39)</span>
          </button>

          <button
            onClick={() => setActiveTab("graph")}
            className={`flex items-center gap-1.5 px-3.5 py-1.5 rounded-xl text-xs font-semibold transition-all ${
              activeTab === "graph"
                ? "bg-[var(--aurora-accent)] text-black shadow-xs"
                : "text-[var(--aurora-fg3)] hover:text-[var(--aurora-fg1)]"
            }`}
          >
            <Icon name="link" size={13} />
            <span>实体知识图谱</span>
          </button>

          <button
            onClick={() => setActiveTab("search")}
            className={`flex items-center gap-1.5 px-3.5 py-1.5 rounded-xl text-xs font-semibold transition-all ${
              activeTab === "search"
                ? "bg-[var(--aurora-accent)] text-black shadow-xs"
                : "text-[var(--aurora-fg3)] hover:text-[var(--aurora-fg1)]"
            }`}
          >
            <Icon name="search" size={13} />
            <span>记忆检索</span>
          </button>
        </div>
      </div>

      {/* ------------------------------------------------------------- */}
      {/* TAB 1: CORE MEMORY TREE */}
      {/* ------------------------------------------------------------- */}
      {activeTab === "tree" && (
        <div className="space-y-4">
          {/* Dimension HUD Metric Bar */}
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

            <Btn variant="glass" icon="grid" onClick={loadMemoryMarkdown}>
              预览 MEMORY.md
            </Btn>
          </div>

          {/* Search filter toolbar */}
          <div className="flex items-center gap-3">
            <div className="flex-1 relative">
              <input
                type="text"
                placeholder="实时过滤 39 个工程、技术标识或规则关键词..."
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
                  ✕
                </button>
              )}
            </div>

            <button
              onClick={() => {
                if (expandedPaths.size > 0) setExpandedPaths(new Set());
                else {
                  const paths = new Set<string>();
                  memoryTree.forEach((r) => {
                    paths.add(r.tree_path);
                    r.children?.forEach((c) => paths.add(c.tree_path));
                  });
                  setExpandedPaths(paths);
                }
              }}
              className="px-3 py-2 rounded-xl bg-[var(--aurora-surface-solid)] border border-[var(--aurora-border)] text-xs text-[var(--aurora-fg2)] hover:border-[var(--aurora-border-strong)] whitespace-nowrap"
            >
              {expandedPaths.size > 0 ? "全部折叠" : "全部展开"}
            </button>
          </div>

          {/* Tree Display */}
          {isTreeLoading ? (
            <div className="py-24 text-center text-xs text-[var(--aurora-fg3)]">
              加载核心记忆树中...
            </div>
          ) : effectiveTree.length === 0 ? (
            <div className="py-16 text-center text-xs text-[var(--aurora-fg3)] bg-[var(--aurora-surface-solid)]/40 rounded-2xl border border-[var(--aurora-border)]">
              未找到匹配「{treeFilter}」的记忆条目
            </div>
          ) : (
            <div className="space-y-3">
              {effectiveTree.map((root) => {
                const isExpanded = expandedPaths.has(root.tree_path);
                const leaves = countLeaves(root);
                const dimColor = CATEGORY_COLORS[root.name] || "#38bdf8";

                return (
                  <div
                    key={root.id}
                    className="rounded-2xl border transition-all overflow-hidden"
                    style={{
                      borderColor: isExpanded ? `${dimColor}44` : "var(--aurora-border)",
                      backgroundColor: "var(--aurora-surface-solid)",
                    }}
                  >
                    {/* Dimension Hero Header */}
                    <div
                      onClick={() => togglePath(root.tree_path)}
                      className="flex items-center gap-3 p-3.5 cursor-pointer hover:bg-[var(--aurora-chip)] transition-colors"
                      style={{
                        background: isExpanded ? `linear-gradient(90deg, ${dimColor}15, transparent)` : "transparent",
                      }}
                    >
                      <div
                        className="w-8 h-8 rounded-lg flex items-center justify-center font-bold text-xs"
                        style={{
                          backgroundColor: `${dimColor}25`,
                          color: dimColor,
                        }}
                      >
                        {root.name === "project" ? "🚀" : root.name === "architecture" ? "🏛️" : root.name === "rules" ? "⚡" : root.name === "tools" ? "🛠️" : "🧠"}
                      </div>

                      <div className="flex-1 min-w-0">
                        <div className="flex items-center gap-2">
                          <span className="font-bold text-sm text-[var(--aurora-fg1)]">
                            {root.title || root.name}
                          </span>
                          <span className="text-[10px] font-mono text-[var(--aurora-fg4)]">
                            {root.tree_path}
                          </span>
                        </div>
                      </div>

                      <span
                        className="px-2.5 py-0.5 rounded-full text-[11px] font-medium"
                        style={{ backgroundColor: `${dimColor}20`, color: dimColor }}
                      >
                        {leaves} 条准则
                      </span>

                      <span className="text-[var(--aurora-fg3)] text-xs ml-1">
                        {isExpanded ? "▼" : "▶"}
                      </span>
                    </div>

                    {/* Children List */}
                    {isExpanded && (
                      <div className="p-3 pt-0 border-t border-[var(--aurora-border)]/50 space-y-2.5">
                        {(root.children || []).map((project) => {
                          const isProjExpanded = expandedPaths.has(project.tree_path);
                          const projLeaves = countLeaves(project);

                          if (project.is_folder) {
                            return (
                              <div
                                key={project.id}
                                className="pl-3 border-l-2 border-[var(--aurora-border-strong)]/60 my-2 space-y-2"
                              >
                                {/* Project Level Item */}
                                <div
                                  onClick={() => togglePath(project.tree_path)}
                                  className="flex items-center justify-between p-2 rounded-xl hover:bg-[var(--aurora-chip)] cursor-pointer text-xs"
                                >
                                  <div className="flex items-center gap-2 min-w-0">
                                    <span className="text-[var(--aurora-fg3)]">📁</span>
                                    <span className="font-semibold text-[var(--aurora-fg1)] truncate">
                                      {project.title || project.name}
                                    </span>
                                    <span className="text-[10px] font-mono px-1.5 py-0.5 rounded bg-[var(--aurora-chip)] text-[var(--aurora-fg3)]">
                                      {project.name}
                                    </span>
                                  </div>
                                  <div className="flex items-center gap-2">
                                    <span className="text-[10px] text-[var(--aurora-fg4)]">
                                      {projLeaves} 条
                                    </span>
                                    <span className="text-[var(--aurora-fg4)] text-[10px]">
                                      {isProjExpanded ? "▼" : "▶"}
                                    </span>
                                  </div>
                                </div>

                                {/* Project Leaf memories */}
                                {isProjExpanded && (
                                  <div className="pl-4 space-y-2">
                                    {(project.children || []).map((leaf) => (
                                      <div
                                        key={leaf.id}
                                        className="relative rounded-xl border border-[var(--aurora-border)] bg-[var(--aurora-surface)]/80 p-3 hover:border-[var(--aurora-border-strong)] transition-all overflow-hidden"
                                      >
                                        {/* Left accent color bar */}
                                        <div
                                          className="absolute left-0 top-0 bottom-0 w-1"
                                          style={{ backgroundColor: dimColor }}
                                        />

                                        <div className="flex items-center justify-between gap-2 mb-1.5">
                                          <div className="flex items-center gap-2">
                                            <span className="font-bold text-xs text-[var(--aurora-fg1)]">
                                              {leaf.key || leaf.title}
                                            </span>
                                            <span
                                              className="text-[9px] font-semibold px-1.5 py-0.2 rounded"
                                              style={{ backgroundColor: `${dimColor}20`, color: dimColor }}
                                            >
                                              {leaf.category.toUpperCase()}
                                            </span>
                                            <span className="text-[9px] px-1.5 py-0.2 rounded bg-[var(--aurora-chip)] text-[var(--aurora-fg3)]">
                                              {leaf.source === "dreaming" ? "🌙 梦境" : leaf.source === "bootstrap" ? "🌟 自举" : "✍️ 手动"}
                                            </span>
                                          </div>

                                          <span className="text-[10px] text-[var(--aurora-fg4)]">
                                            {((leaf.confidence || 1) * 100).toFixed(0)}% 置信
                                          </span>
                                        </div>

                                        <p className="text-xs text-[var(--aurora-fg2)] leading-relaxed mb-2">
                                          {leaf.content}
                                        </p>

                                        <div className="flex items-center justify-between text-[10px] text-[var(--aurora-fg4)] font-mono border-t border-[var(--aurora-border)]/40 pt-1.5">
                                          <span>{leaf.tree_path}</span>
                                          <button
                                            onClick={(e) => {
                                              e.stopPropagation();
                                              copyPath(leaf.tree_path);
                                            }}
                                            className="hover:text-[var(--aurora-accent)] transition-colors flex items-center gap-1"
                                          >
                                            {copyFeedback === leaf.tree_path ? "✓ 已复制" : "复制路径"}
                                          </button>
                                        </div>
                                      </div>
                                    ))}
                                  </div>
                                )}
                              </div>
                            );
                          }

                          return null;
                        })}
                      </div>
                    )}
                  </div>
                );
              })}
            </div>
          )}
        </div>
      )}

      {/* ------------------------------------------------------------- */}
      {/* TAB 2: KNOWLEDGE GRAPH */}
      {/* ------------------------------------------------------------- */}
      {activeTab === "graph" && (
        <div className="space-y-4">
          {stats && (
            <div className="grid grid-cols-2 md:grid-cols-4 gap-3 sm:gap-4">
              <StatCard label="Entities" value={stats.entities} />
              <StatCard label="Relations" value={stats.relations} />
              <StatCard label="Observations" value={stats.observations} />
              <StatCard label="Embeddings" value={stats.embeddings} />
            </div>
          )}

          <div style={{ display: "flex", gap: 10, flexWrap: "wrap" }}>
            <label className="aurora-input" style={{ minWidth: 200 }}>
              <Icon name="grid" size={15} style={{ color: "var(--aurora-fg3)" }} />
              <select value={filterType} onChange={(e) => setFilterType(e.target.value)}>
                <option value="">All Types</option>
                {stats && Object.entries(stats.entity_types).map(([type, count]) => (
                  <option key={type} value={type}>{type} ({count})</option>
                ))}
              </select>
            </label>
            <GhostInput
              type="text"
              placeholder="Search entities & observations…"
              value={searchQuery}
              onChange={(e) => setSearchQuery(e.target.value)}
              onKeyDown={(e) => e.key === "Enter" && handleSearch()}
              icon="search"
              wrapStyle={{ flex: 1, minWidth: 260 }}
            />
            <Btn onClick={handleSearch} icon="search">Search</Btn>
            <Btn variant="glass" icon="link" onClick={() => setShareOpen(true)}>
              {t.memoryShare.button}
            </Btn>
          </div>

          <div className="grid grid-cols-1 lg:grid-cols-3 gap-4 sm:gap-6">
            <div className="lg:col-span-2 aurora-card" style={{ padding: 0, overflow: "hidden" }}>
              <div style={{ padding: 14, borderBottom: "1px solid var(--aurora-border)", display: "flex", alignItems: "center", justifyContent: "space-between" }}>
                <h3 style={{ fontSize: 12, fontWeight: 600, color: "var(--aurora-fg3)", textTransform: "uppercase", letterSpacing: "0.04em" }}>
                  Knowledge Graph
                </h3>
                <span style={{ fontSize: 11, color: "var(--aurora-fg4)" }}>
                  {nodes.length} nodes · {edges.length} edges
                </span>
              </div>
              {nodes.length === 0 ? (
                <div style={{ padding: 48, textAlign: "center", color: "var(--aurora-fg4)", fontSize: 13 }}>
                  No entities yet. Memory builds automatically as you use AI tools.
                </div>
              ) : (
                <svg
                  ref={svgRef}
                  viewBox="0 0 800 600"
                  className="w-full h-[400px] sm:h-[500px]"
                >
                  {edges.map((e, i) => {
                    const s = nodeMap.get(e.source);
                    const t = nodeMap.get(e.target);
                    if (!s || !t) return null;
                    return (
                      <g key={`e-${i}`}>
                        <line
                          x1={s.x} y1={s.y} x2={t.x} y2={t.y}
                          stroke="var(--aurora-border-strong)" strokeWidth={Math.min(e.strength, 3)}
                        />
                        <text
                          x={((s.x || 0) + (t.x || 0)) / 2}
                          y={((s.y || 0) + (t.y || 0)) / 2 - 4}
                          fill="var(--aurora-fg4)" fontSize="8" textAnchor="middle"
                        >
                          {e.type}
                        </text>
                      </g>
                    );
                  })}
                  {nodes.map((n) => (
                    <g
                      key={n.id}
                      transform={`translate(${n.x || 0},${n.y || 0})`}
                      onClick={() => handleNodeClick(n.id)}
                      className="cursor-pointer"
                    >
                      <circle
                        r={12}
                        fill={TYPE_COLORS[n.type] || "#6b7280"}
                        opacity={0.85}
                        stroke={selectedEntity?.id === n.id ? "var(--aurora-accent)" : "var(--aurora-surface-solid)"}
                        strokeWidth={selectedEntity?.id === n.id ? 3 : 1.5}
                      />
                      <text
                        dy={24} textAnchor="middle"
                        fill="var(--aurora-fg2)" fontSize="10" fontWeight="500"
                      >
                        {n.name.length > 15 ? n.name.slice(0, 15) + "..." : n.name}
                      </text>
                    </g>
                  ))}
                </svg>
              )}
              <div style={{ padding: 12, borderTop: "1px solid var(--aurora-border)", display: "flex", flexWrap: "wrap", gap: 12 }}>
                {Object.entries(TYPE_COLORS).map(([type, color]) => (
                  <div key={type} style={{ display: "flex", alignItems: "center", gap: 6, fontSize: 11, color: "var(--aurora-fg3)" }}>
                    <span style={{ width: 10, height: 10, borderRadius: 9999, background: color }} />
                    {type}
                  </div>
                ))}
              </div>
            </div>

            <Glass padding={20} radius={20}>
              {selectedEntity ? (
                <>
                  <div style={{ display: "flex", alignItems: "center", gap: 10, marginBottom: 14 }}>
                    <div
                      style={{
                        width: 32, height: 32, borderRadius: 10,
                        background: (TYPE_COLORS[selectedEntity.type] || "#6b7280") + "22",
                        color: TYPE_COLORS[selectedEntity.type] || "#6b7280",
                        display: "flex", alignItems: "center", justifyContent: "center",
                      }}
                    >
                      <Icon name="target" size={16} />
                    </div>
                    <div>
                      <h3 style={{ margin: 0, fontSize: 15, fontWeight: 600, color: "var(--aurora-fg1)", letterSpacing: "-0.01em" }}>
                        {selectedEntity.name}
                      </h3>
                      <span
                        style={{
                          display: "inline-block",
                          marginTop: 2,
                          fontSize: 10.5,
                          padding: "2px 8px",
                          borderRadius: 9999,
                          background: (TYPE_COLORS[selectedEntity.type] || "#6b7280") + "22",
                          color: TYPE_COLORS[selectedEntity.type] || "#6b7280",
                          fontWeight: 500,
                        }}
                      >
                        {selectedEntity.type}
                      </span>
                    </div>
                  </div>
                  {selectedEntity.summary && (
                    <p style={{ fontSize: 13, color: "var(--aurora-fg3)", marginBottom: 14, lineHeight: 1.5 }}>
                      {selectedEntity.summary}
                    </p>
                  )}
                  {(selectedEntity.outgoing_relations.length > 0 || selectedEntity.incoming_relations.length > 0) && (
                    <div style={{ marginBottom: 14 }}>
                      <h4 style={{ fontSize: 10.5, fontWeight: 600, color: "var(--aurora-fg4)", textTransform: "uppercase", letterSpacing: "0.06em", marginBottom: 6 }}>
                        Relations
                      </h4>
                      <div style={{ display: "flex", flexDirection: "column", gap: 4 }}>
                        {selectedEntity.outgoing_relations.map((r, i) => (
                          <div key={`o-${i}`} style={{ fontSize: 12, color: "var(--aurora-fg3)" }}>
                            → <span style={{ color: "var(--aurora-accent)", fontWeight: 500 }}>{r.relation}</span> → <span style={{ color: "var(--aurora-fg1)", fontWeight: 500 }}>{r.target_name}</span>
                          </div>
                        ))}
                        {selectedEntity.incoming_relations.map((r, i) => (
                          <div key={`i-${i}`} style={{ fontSize: 12, color: "var(--aurora-fg3)" }}>
                            <span style={{ color: "var(--aurora-fg1)", fontWeight: 500 }}>{r.source_name}</span> → <span style={{ color: "var(--aurora-accent)", fontWeight: 500 }}>{r.relation}</span> →
                          </div>
                        ))}
                      </div>
                    </div>
                  )}
                  {selectedEntity.observations.length > 0 && (
                    <div>
                      <h4 style={{ fontSize: 10.5, fontWeight: 600, color: "var(--aurora-fg4)", textTransform: "uppercase", letterSpacing: "0.06em", marginBottom: 6 }}>
                        Observations ({selectedEntity.observations.length})
                      </h4>
                      <div style={{ display: "flex", flexDirection: "column", gap: 8, maxHeight: 260, overflowY: "auto" }}>
                        {selectedEntity.observations.map((o, i) => (
                          <div key={i} style={{ fontSize: 12, color: "var(--aurora-fg3)", borderLeft: "2px solid var(--aurora-border-strong)", paddingLeft: 8 }}>
                            <p style={{ margin: 0 }}>{o.content}</p>
                            {o.observed_at && (
                              <span style={{ fontSize: 10.5, color: "var(--aurora-fg4)" }}>{new Date(o.observed_at).toLocaleDateString()}</span>
                            )}
                          </div>
                        ))}
                      </div>
                    </div>
                  )}
                </>
              ) : (
                <div style={{ textAlign: "center", color: "var(--aurora-fg4)", fontSize: 13, padding: "32px 0" }}>
                  Click a node to view details
                </div>
              )}
            </Glass>
          </div>
        </div>
      )}

      {/* ------------------------------------------------------------- */}
      {/* TAB 3: SEARCH RESULTS */}
      {/* ------------------------------------------------------------- */}
      {activeTab === "search" && (
        <div className="space-y-4">
          <div className="flex gap-2">
            <GhostInput
              type="text"
              placeholder="跨设备搜索研发会话与记忆..."
              value={searchQuery}
              onChange={(e) => setSearchQuery(e.target.value)}
              onKeyDown={(e) => e.key === "Enter" && handleSearch()}
              icon="search"
              wrapStyle={{ flex: 1 }}
            />
            <Btn onClick={handleSearch} icon="search">检索</Btn>
          </div>

          {searchResults.length > 0 ? (
            <Glass padding={16} radius={18}>
              <h3 style={{ fontSize: 12, fontWeight: 600, color: "var(--aurora-fg3)", textTransform: "uppercase", letterSpacing: "0.04em", marginBottom: 12 }}>
                Search Results ({searchResults.length})
              </h3>
              <div style={{ display: "flex", flexDirection: "column", gap: 8 }}>
                {searchResults.map((r, i) => (
                  <div key={i} style={{ display: "flex", alignItems: "flex-start", gap: 10, fontSize: 13 }} className="p-2 rounded-xl hover:bg-[var(--aurora-chip)] transition-colors">
                    <div
                      style={{
                        width: 18, height: 18, borderRadius: 9999,
                        background: TYPE_COLORS[r.entity_type || r.type || ""] || "#6b7280",
                        flexShrink: 0,
                        marginTop: 2,
                      }}
                    />
                    <div style={{ flex: 1, minWidth: 0 }}>
                      <div className="flex items-center gap-2">
                        <span style={{ fontWeight: 600, color: "var(--aurora-fg1)" }}>{r.name}</span>
                        <span style={{ fontSize: 10, color: "var(--aurora-fg4)", padding: "1px 6px", borderRadius: 4, background: "var(--aurora-chip)" }}>
                          {r.entity_type || r.type || ""}
                        </span>
                      </div>
                      {r.summary && <p style={{ fontSize: 12, color: "var(--aurora-fg2)", marginTop: 4 }}>{r.summary}</p>}
                      {r.content && <p style={{ fontSize: 12, color: "var(--aurora-fg3)", marginTop: 4 }}>{r.content.slice(0, 180)}...</p>}
                    </div>
                  </div>
                ))}
              </div>
            </Glass>
          ) : (
            <div className="py-20 text-center text-xs text-[var(--aurora-fg3)] bg-[var(--aurora-surface-solid)]/30 rounded-2xl border border-[var(--aurora-border)]">
              输入关键词检索跨设备的编程记忆、代码与文档
            </div>
          )}
        </div>
      )}

      {/* Share Modal */}
      <ShareModal
        open={shareOpen}
        onClose={() => setShareOpen(false)}
        kind="memory"
        targetId="all"
        title={t.nav.memory}
      />

      {/* MEMORY.md Full Markdown Modal */}
      {markdownModalOpen && (
        <div className="fixed inset-0 z-50 flex items-center justify-center p-4 bg-black/60 backdrop-blur-xs">
          <div className="relative w-full max-w-3xl max-h-[85vh] bg-[var(--aurora-surface-solid)] border border-[var(--aurora-border-strong)] rounded-2xl flex flex-col shadow-2xl overflow-hidden">
            <div className="flex items-center justify-between px-5 py-3.5 border-b border-[var(--aurora-border)] bg-[var(--aurora-surface)]">
              <div className="flex items-center gap-2">
                <span className="text-[var(--aurora-accent)]">📖</span>
                <span className="font-bold text-sm text-[var(--aurora-fg1)]">MEMORY.md 全文预览</span>
              </div>
              <button
                onClick={() => setMarkdownModalOpen(false)}
                className="w-7 h-7 rounded-lg flex items-center justify-center text-[var(--aurora-fg3)] hover:text-[var(--aurora-fg1)] hover:bg-[var(--aurora-chip)] text-xs"
              >
                ✕
              </button>
            </div>

            <div className="p-6 overflow-y-auto max-h-[calc(85vh-60px)]">
              <MarkdownViewer content={markdownContent} />
            </div>
          </div>
        </div>
      )}
    </div>
  );
}
