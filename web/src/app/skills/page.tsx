"use client";

import { useCallback, useEffect, useMemo, useRef, useState, type CSSProperties } from "react";
import { api } from "@/lib/api-client";
import { fmt, useI18n } from "@/lib/i18n";
import { Btn, Chip, Glass } from "@/components/aurora/primitives";
import { Icon } from "@/components/aurora/Icon";
import MarkdownViewer from "@/components/viewers/MarkdownViewer";
import CognitiveCompass from "@/components/memory/CognitiveCompass";

type Obj = Record<string, unknown>;
const obj = (v: unknown): Obj => (v && typeof v === "object" && !Array.isArray(v) ? (v as Obj) : {});
const list = (v: unknown): Obj[] => (Array.isArray(v) ? v.filter((x) => x && typeof x === "object") : []) as Obj[];
const num = (v: unknown): number => (typeof v === "number" ? v : 0);
const str = (v: unknown): string => (v == null ? "" : String(v));
const count = (v: unknown): number => (Array.isArray(v) ? v.length : 0);

function time(iso: unknown): string {
  if (typeof iso !== "string") return "";
  const d = new Date(iso);
  if (Number.isNaN(d.getTime())) return "";
  const two = (n: number) => String(n).padStart(2, "0");
  return `${d.getMonth() + 1}-${d.getDate()} ${two(d.getHours())}:${two(d.getMinutes())}`;
}

const mono: CSSProperties = { fontFamily: "ui-monospace, SFMono-Regular, Menlo, monospace" };
const field: CSSProperties = {
  width: "100%",
  fontSize: 13,
  padding: "8px 12px",
  borderRadius: 12,
  border: "1px solid var(--aurora-border-strong)",
  background: "var(--aurora-surface-solid)",
  color: "var(--aurora-fg1)",
};

/** Per-device write results collapsed into counts by kind. */
function skillResultCounts(results: Obj | undefined): Record<string, number> {
  const counts: Record<string, number> = {};
  for (const v of Object.values(results ?? {})) {
    const s = String(v);
    const kind = s.startsWith("error") ? "error" : s.startsWith("skipped") ? "skipped" : s.startsWith("kept") ? "kept" : s === "removed" ? "removed" : "ok";
    counts[kind] = (counts[kind] ?? 0) + 1;
  }
  return counts;
}

function SkillEditor({ skill, busy, onSave, onCancel }: { skill: Obj; busy: boolean; onSave: (edits: Obj, publish: boolean) => void; onCancel: () => void }) {
  const { t } = useI18n();
  const s = t.skills;
  const [title, setTitle] = useState(str(skill.title));
  const [slug, setSlug] = useState(str(skill.slug));
  const [description, setDescription] = useState(str(skill.description));
  const [body, setBody] = useState(str(skill.body));
  const isDraft = skill.status === "draft";
  const edits = { title: title.trim(), slug: slug.trim(), description: description.trim(), body };
  const label = (text: string, hint?: string) => (
    <div style={{ fontSize: 12, color: "var(--aurora-fg3)", margin: "10px 0 4px" }}>
      {text}
      {hint && <span style={{ color: "var(--aurora-fg4)" }}> · {hint}</span>}
    </div>
  );
  return (
    <div className="mt-3 p-4 rounded-2xl bg-[var(--aurora-surface-mute)] border border-[var(--aurora-border)]">
      {label(s.fieldTitle)}
      <input value={title} onChange={(e) => setTitle(e.target.value)} style={field} />
      {label(s.fieldSlug, s.fieldSlugHint)}
      <input value={slug} onChange={(e) => setSlug(e.target.value)} style={{ ...field, ...mono }} />
      {label(s.fieldDescription, s.fieldDescriptionHint)}
      <textarea value={description} onChange={(e) => setDescription(e.target.value)} rows={3} style={{ ...field, resize: "vertical" }} />
      {label(s.fieldBody)}
      <textarea value={body} onChange={(e) => setBody(e.target.value)} rows={14} style={{ ...field, ...mono, lineHeight: 1.55, resize: "vertical" }} />
      <div style={{ display: "flex", gap: 8, justifyContent: "flex-end", marginTop: 12, flexWrap: "wrap" }}>
        <Btn variant="ghost" size="sm" onClick={onCancel} disabled={busy}>
          {t.cancel}
        </Btn>
        {isDraft && (
          <Btn variant="glass" size="sm" onClick={() => onSave(edits, false)} disabled={busy}>
            {s.save}
          </Btn>
        )}
        <Btn size="sm" icon="rocket" onClick={() => onSave(edits, true)} disabled={busy || !edits.title || !edits.slug}>
          {isDraft ? s.saveAndPublish : s.saveNewVersion}
        </Btn>
      </div>
    </div>
  );
}

export default function SkillsPage() {
  const { t } = useI18n();
  const s = t.skills;
  const [data, setData] = useState<Obj | null>(null);
  const [reviews, setReviews] = useState<Obj>({});
  const [error, setError] = useState<string | null>(null);
  const [notice, setNotice] = useState<string | null>(null);
  const [busy, setBusy] = useState<string | null>(null);
  const [expanded, setExpanded] = useState<Set<string>>(new Set());
  const [editing, setEditing] = useState<string | null>(null);
  const [showUpdate, setShowUpdate] = useState<string | null>(null);
  const [activeTab, setActiveTab] = useState<"published" | "drafts" | "reviews" | "archived">("published");
  const poll = useRef<ReturnType<typeof setInterval> | null>(null);

  const job = reviews.job ? obj(reviews.job) : null;
  const reviewRunning = job?.status === "running";

  const load = useCallback(async () => {
    try {
      const [skills, rev] = await Promise.all([api.getSkills(), api.getReviews().catch(() => ({}))]);
      setData(skills);
      setReviews(rev);
      setError(null);
      return obj(obj(rev).job).status === "running";
    } catch (e) {
      const msg = (e as Error).message;
      setError(msg.includes("404") ? s.tooOld : msg);
      return false;
    }
  }, [s]);

  const jobSummary = useCallback(
    (j: Obj) => {
      if (j.status === "error") return fmt(s.reviewError, { error: str(j.error) });
      const sessions = obj(obj(j.result).sessions);
      const reviewed = num(sessions.reviewed);
      if (reviewed === 0) return s.reviewNothing;
      return fmt(s.reviewDone, { n: reviewed, skills: count(sessions.skills_new), pitfalls: num(sessions.pitfalls_new), todos: num(sessions.todos_new) });
    },
    [s],
  );

  const startPolling = useCallback(() => {
    if (poll.current) return;
    poll.current = setInterval(async () => {
      const running = await load();
      if (!running && poll.current) {
        clearInterval(poll.current);
        poll.current = null;
        const rev = await api.getReviews().catch(() => ({}) as Obj);
        if (obj(rev).job) setNotice(jobSummary(obj(obj(rev).job)));
      }
    }, 5000);
  }, [load, jobSummary]);

  useEffect(() => {
    load().then((running) => running && startPolling());
    return () => {
      if (poll.current) clearInterval(poll.current);
    };
  }, [load, startPolling]);

  const act = async (id: string, action: () => Promise<unknown>, done?: string) => {
    setBusy(id);
    setNotice(null);
    try {
      await action();
      if (done) setNotice(done);
      setEditing(null);
      await load();
    } catch (e) {
      setError((e as Error).message);
    } finally {
      setBusy(null);
    }
  };

  const reviewNow = async () => {
    setBusy("review");
    setNotice(null);
    try {
      await api.startReview();
      setNotice(s.reviewStarted);
      await load();
      startPolling();
    } catch (e) {
      setError((e as Error).message);
    } finally {
      setBusy(null);
    }
  };

  const toggle = (id: string) =>
    setExpanded((prev) => {
      const next = new Set(prev);
      if (next.has(id)) next.delete(id);
      else next.add(id);
      return next;
    });

  const drafts = list(data?.drafts);
  const published = list(data?.published);
  const archived = list(data?.archived);
  const devices = list(data?.devices);
  const statusLabels: Record<string, string> = { draft: s.statusDraft, published: s.statusPublished, dismissed: s.statusDismissed, retired: s.statusRetired };

  const reviewList = list(reviews.reviews);
  const stats = obj(reviews.stats);
  const outcomes = obj(stats.outcomes);
  const outcomeLabels: Record<string, string> = { done: s.outcomeDone, partial: s.outcomePartial, failed: s.outcomeFailed, chat: s.outcomeChat, error: s.outcomeError, unknown: s.outcomeUnknown };
  const outcomeTone = (o: string) => (o === "done" ? "success" : o === "failed" || o === "error" ? "danger" : o === "partial" ? "warn" : "neutral");

  const learned = (r: Obj) => {
    const parts: string[] = [];
    if (r.skill != null) {
      parts.push(r.skill_event === "new" ? fmt(s.learnedNewSkill, { skill: str(r.skill) }) : r.skill_event === "update_pending" ? fmt(s.learnedSkillUpdate, { skill: str(r.skill) }) : fmt(s.learnedSkillUsed, { skill: str(r.skill) }));
    }
    if (num(r.pitfalls_new) > 0) parts.push(fmt(s.learnedPitfalls, { n: num(r.pitfalls_new) }));
    if (count(r.pitfalls_seen) > 0) parts.push(fmt(s.learnedRepeats, { n: count(r.pitfalls_seen) }));
    if (num(r.todos_new) > 0) parts.push(fmt(s.learnedTodos, { n: num(r.todos_new) }));
    if (num(r.todos_done) > 0) parts.push(fmt(s.learnedTodosDone, { n: num(r.todos_done) }));
    return parts.length ? parts.join(" · ") : s.learnedNothing;
  };

  const deviceSummary = (d: Obj) => {
    if (count(d.targets) === 0) return s.deviceNoTools;
    const devStatus = obj(d.status);
    if (!devStatus.results) return s.deviceWaiting;
    const c = skillResultCounts(obj(devStatus.results));
    const parts = [
      c.ok ? fmt(s.deviceWritten, { n: c.ok }) : "",
      c.kept ? fmt(s.deviceKept, { n: c.kept }) : "",
      c.skipped ? fmt(s.deviceSkipped, { n: c.skipped }) : "",
      c.error ? fmt(s.deviceErrors, { n: c.error }) : "",
    ].filter(Boolean);
    return `${parts.length ? parts.join(" · ") : s.deviceNoSkills} · ${time(devStatus.reported_at)}`;
  };

  const renderSkillCard = (skill: Obj) => {
    const id = str(skill.id);
    const status = str(skill.status) || "draft";
    const disabled = busy !== null;
    const update = skill.pending_update ? obj(skill.pending_update) : null;
    const evidence = list(skill.evidence);
    const isExpanded = expanded.has(id);

    return (
      <div
        key={id}
        className="p-5 rounded-2xl border border-[var(--aurora-border)] bg-[var(--aurora-surface)] shadow-xs hover:border-[var(--aurora-border-strong)] transition-all flex flex-col justify-between"
      >
        <div>
          {/* Card Header */}
          <div className="flex items-start justify-between gap-3 pb-3 mb-3 border-b border-[var(--aurora-border)]">
            <div className="flex items-center gap-2.5">
              <div className="w-8 h-8 rounded-xl flex items-center justify-center bg-[rgba(245,158,11,0.12)] text-[#F59E0B]">
                <Icon name="zap" size={16} />
              </div>
              <div>
                <h3 className="text-sm font-bold text-[var(--aurora-fg1)]">
                  {str(skill.title)}
                </h3>
                <span className="text-[11px] font-mono text-[var(--aurora-fg4)]">
                  /{str(skill.slug)}
                </span>
              </div>
            </div>

            <div className="flex items-center gap-1.5 shrink-0">
              <span className="text-[10px] font-mono px-2 py-0.5 rounded-full bg-[var(--aurora-chip)] text-[var(--aurora-fg2)] font-semibold">
                {status === "published" ? `v${str(skill.version || "1.0")}` : "草稿"}
              </span>
              {skill.project ? (
                <span className="text-[10px] px-2 py-0.5 rounded-full bg-[rgba(16,185,129,0.1)] text-[#10B981] font-medium">
                  {str(skill.project)}
                </span>
              ) : null}
            </div>
          </div>

          <p className="text-xs text-[var(--aurora-fg2)] leading-relaxed mb-4">
            {str(skill.description)}
          </p>

          {/* Update Notice */}
          {update && (
            <div className="mb-3 p-3 rounded-xl bg-[rgba(217,119,6,0.08)] border border-[rgba(217,119,6,0.25)] text-xs">
              <div className="font-semibold text-[#B45309] mb-1">发现新版技能演进建议：</div>
              <p className="text-[var(--aurora-fg3)]">{str(update.reason)}</p>
              {showUpdate === id && (
                <div className="mt-2 pt-2 border-t border-[rgba(217,119,6,0.2)] prose prose-sm max-w-none text-xs">
                  <MarkdownViewer content={str(update.body)} />
                </div>
              )}
              <div className="flex gap-2 justify-end mt-2">
                <Btn variant="ghost" size="sm" onClick={() => act(id, () => api.skillAction(id, "update/discard"))}>忽略</Btn>
                <Btn variant="glass" size="sm" onClick={() => setShowUpdate(showUpdate === id ? null : id)}>
                  {showUpdate === id ? "收起" : "对比变更"}
                </Btn>
                <Btn size="sm" onClick={() => act(id, () => api.skillAction(id, "update/apply"), s.updateApplied)}>应用更新</Btn>
              </div>
            </div>
          )}

          {/* Expanded Step Body */}
          {isExpanded && (
            <div className="mb-3 p-3.5 rounded-xl bg-[var(--aurora-surface-solid)] border border-[var(--aurora-border)]">
              <div className="prose prose-sm max-w-none text-xs leading-relaxed">
                <MarkdownViewer content={str(skill.body)} />
              </div>
              {evidence.length > 0 && (
                <div className="mt-2.5 pt-2 border-t border-[var(--aurora-border)] text-[11px] text-[var(--aurora-fg4)]">
                  提炼自最近真实操作会话：{str(evidence[evidence.length - 1]?.title || "日常编码实践")}
                </div>
              )}
            </div>
          )}
        </div>

        {/* Card Footer Actions */}
        <div className="pt-3 border-t border-[var(--aurora-border)] flex items-center justify-between">
          <button
            type="button"
            onClick={() => toggle(id)}
            className="text-xs text-[var(--aurora-accent)] hover:underline flex items-center gap-1 font-medium"
          >
            <Icon name={isExpanded ? "minus" : "plus"} size={11} />
            <span>{isExpanded ? "收起步骤指令" : "查看执行指令"}</span>
          </button>

          <div className="flex items-center gap-1.5">
            {status === "draft" && (
              <>
                <Btn variant="ghost" size="sm" disabled={disabled} onClick={() => act(id, () => api.skillAction(id, "dismiss"))}>
                  放弃
                </Btn>
                <Btn variant="glass" size="sm" icon="edit" disabled={disabled} onClick={() => setEditing(id)}>
                  编辑
                </Btn>
                <Btn size="sm" icon="rocket" disabled={disabled} onClick={() => act(id, () => api.publishSkill(id), s.publishedNotice)}>
                  发布
                </Btn>
              </>
            )}
            {status === "published" && (
              <>
                <Btn variant="ghost" size="sm" disabled={disabled} onClick={() => act(id, () => api.skillAction(id, "retire"), s.retiredNotice)}>
                  归档
                </Btn>
                <Btn variant="glass" size="sm" icon="edit" disabled={disabled} onClick={() => setEditing(id)}>
                  微调
                </Btn>
              </>
            )}
          </div>
        </div>

        {editing === id && (
          <SkillEditor
            skill={skill}
            busy={disabled}
            onCancel={() => setEditing(null)}
            onSave={(edits, publish) =>
              publish && status === "draft"
                ? act(id, () => api.publishSkill(id, edits), s.publishedNotice)
                : act(id, () => api.editSkill(id, edits), status === "draft" ? s.saved : s.savedNewVersion)
            }
          />
        )}
      </div>
    );
  };

  return (
    <div className="max-w-6xl mx-auto space-y-6 pb-20">
      {/* ─────────────────────────────────────────────────────────────
          1. 统一顶栏 (Single-Row Modern Header)
          ───────────────────────────────────────────────────────────── */}
      <div className="flex flex-col sm:flex-row sm:items-center justify-between gap-4 pb-2 border-b border-[var(--aurora-border)]">
        <div>
          <div className="flex items-center gap-2.5">
            <div className="w-8 h-8 rounded-xl flex items-center justify-center bg-[rgba(245,158,11,0.12)] text-[#F59E0B] shadow-xs">
              <Icon name="zap" size={18} />
            </div>
            <h1 className="text-xl font-bold text-[var(--aurora-fg1)] tracking-tight">
              技能进化 · 特长与工具箱
            </h1>
            <span className="text-[11px] px-2.5 py-0.5 rounded-full font-medium bg-[rgba(16,185,129,0.12)] text-[#10B981] flex items-center gap-1.5">
              <span className="w-1.5 h-1.5 rounded-full bg-[#10B981] breathing-glow-emerald" />
              Agent Skill 协议就绪
            </span>
          </div>
          <p className="text-xs text-[var(--aurora-fg3)] mt-1 ml-10">
            AI 会执行什么 · 从高频操作中沉淀出标准 SOP、自动化执行脚本与工业级专业本领
          </p>
        </div>

        <div className="flex items-center gap-2 self-start sm:self-auto">
          <Btn
            variant="glass"
            size="sm"
            icon="refresh"
            disabled={reviewRunning || busy !== null}
            onClick={reviewNow}
          >
            {reviewRunning ? s.reviewing : "自动审查提炼技能"}
          </Btn>
        </div>
      </div>

      {/* ─────────────────────────────────────────────────────────────
          Cognitive Brain 3-Pillars Executive Compass Navigation
          ───────────────────────────────────────────────────────────── */}
      <CognitiveCompass
        currentTab="skills"
        summaryStats={{
          skillsCount: count(data?.published) + count(data?.drafts),
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
          2. Hero 技能进化大屏 (Skill Evolution Cockpit)
          ───────────────────────────────────────────────────────────── */}
      <div className="relative overflow-hidden rounded-3xl p-6 sm:p-8 border border-[var(--aurora-border)] bg-gradient-to-br from-[var(--aurora-surface)] via-[var(--aurora-surface)] to-[rgba(245,158,11,0.06)] shadow-sm">
        <div className="flex flex-col md:flex-row md:items-center justify-between gap-6">
          <div className="space-y-2 max-w-xl">
            <span className="text-[11px] font-mono uppercase tracking-widest text-[#F59E0B] font-semibold">
              Autonomous Skill Library · v1.0
            </span>
            <h2 className="text-2xl sm:text-3xl font-extrabold text-[var(--aurora-fg1)] tracking-tight">
              赋予 AI 执行专业任务的硬核本领。
            </h2>
            <p className="text-xs sm:text-sm text-[var(--aurora-fg2)] leading-relaxed">
              支持工业级标准 `SKILL.md` 规范。通过 Memento 的日常会话复盘，系统自动发掘高价值可复用动作，沉淀为开箱即用的自动化工具，全端设备秒级下发生效。
            </p>
          </div>

          {/* Quick Metrics */}
          <div className="flex gap-4 shrink-0 bg-[var(--aurora-surface-solid)] p-4 rounded-2xl border border-[var(--aurora-border)] shadow-xs">
            <div className="px-3 border-r border-[var(--aurora-border)]">
              <div className="text-[11px] text-[var(--aurora-fg3)]">活跃技能</div>
              <div className="text-2xl font-bold font-mono text-[#F59E0B] mt-0.5">
                {published.length}
                <span className="text-xs font-normal text-[var(--aurora-fg4)] ml-1">项</span>
              </div>
            </div>
            <div className="px-3 border-r border-[var(--aurora-border)]">
              <div className="text-[11px] text-[var(--aurora-fg3)]">待审提炼</div>
              <div className="text-2xl font-bold font-mono text-[var(--aurora-fg1)] mt-0.5">
                {drafts.length}
                <span className="text-xs font-normal text-[var(--aurora-fg4)] ml-1">条</span>
              </div>
            </div>
            <div className="px-3">
              <div className="text-[11px] text-[var(--aurora-fg3)]">跨端分发</div>
              <div className="text-2xl font-bold font-mono text-[#10B981] mt-0.5">
                {devices.length || 1}
                <span className="text-xs font-normal text-[var(--aurora-fg4)] ml-1">台</span>
              </div>
            </div>
          </div>
        </div>
      </div>

      {/* ─────────────────────────────────────────────────────────────
          3. 胶囊过滤器 (Filter Pills)
          ───────────────────────────────────────────────────────────── */}
      <div className="flex items-center gap-1.5 p-1 rounded-2xl bg-[var(--aurora-surface)] border border-[var(--aurora-border)] shadow-xs self-start">
        {[
          { id: "published" as const, label: `活跃技能 (${published.length})`, icon: "zap" as const },
          { id: "drafts" as const, label: `待审草稿 (${drafts.length})`, icon: "edit" as const },
          { id: "reviews" as const, label: `审查动态 (${reviewList.length})`, icon: "sparkles" as const },
          { id: "archived" as const, label: `历史归档 (${archived.length})`, icon: "minus" as const },
        ].map((tab) => {
          const active = activeTab === tab.id;
          return (
            <button
              key={tab.id}
              onClick={() => setActiveTab(tab.id)}
              className={`flex items-center gap-1.5 px-3.5 py-1.5 rounded-xl text-xs font-medium transition-all ${
                active
                  ? "bg-[var(--aurora-surface-solid)] text-[#F59E0B] shadow-xs font-semibold"
                  : "text-[var(--aurora-fg3)] hover:text-[var(--aurora-fg1)] hover:bg-[var(--aurora-chip)]"
              }`}
            >
              <Icon name={tab.icon} size={13} />
              <span>{tab.label}</span>
            </button>
          );
        })}
      </div>

      {/* ─────────────────────────────────────────────────────────────
          4. 技能网格 (Bento Skill Cards)
          ───────────────────────────────────────────────────────────── */}
      {activeTab === "published" && (
        <div>
          {published.length > 0 ? (
            <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
              {published.map(renderSkillCard)}
            </div>
          ) : (
            <Glass padding={24} radius={18} className="text-center text-xs text-[var(--aurora-fg3)]">
              暂无已发布的活跃技能，请在上方点击「自动审查提炼技能」发掘日常编码 SOP。
            </Glass>
          )}
        </div>
      )}

      {activeTab === "drafts" && (
        <div>
          {drafts.length > 0 ? (
            <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
              {drafts.map(renderSkillCard)}
            </div>
          ) : (
            <Glass padding={24} radius={18} className="text-center text-xs text-[var(--aurora-fg3)]">
              暂无待审阅的草稿技能。系统在夜间或手动审查时会自动提炼新技能。
            </Glass>
          )}
        </div>
      )}

      {activeTab === "reviews" && (
        <div className="space-y-3">
          {reviewList.length > 0 ? (
            reviewList.slice(0, 20).map((r, i) => (
              <div
                key={i}
                className="p-4 rounded-2xl border border-[var(--aurora-border)] bg-[var(--aurora-surface)] shadow-xs flex flex-col gap-1.5"
              >
                <div className="flex items-center justify-between gap-2">
                  <div className="flex items-center gap-2">
                    <Chip tone={outcomeTone(str(r.outcome))}>{outcomeLabels[str(r.outcome)] ?? str(r.outcome)}</Chip>
                    <span className="font-semibold text-xs text-[var(--aurora-fg1)] truncate max-w-md">{str(r.title)}</span>
                  </div>
                  <span className="text-[11px] font-mono text-[var(--aurora-fg4)]">{time(r.reviewed_at)}</span>
                </div>
                {str(r.summary) && (
                  <p className="text-xs text-[var(--aurora-fg2)] leading-relaxed mt-1">{str(r.summary)}</p>
                )}
                <div className="text-[11px] text-[var(--aurora-fg3)] mt-1 font-mono">
                  {learned(obj(r.result))}
                </div>
              </div>
            ))
          ) : (
            <Glass padding={24} radius={18} className="text-center text-xs text-[var(--aurora-fg3)]">
              暂无审查会话记录
            </Glass>
          )}
        </div>
      )}

      {activeTab === "archived" && (
        <div className="space-y-3">
          {archived.length > 0 ? (
            archived.map((a) => (
              <div
                key={str(a.id)}
                className="p-4 rounded-2xl border border-[var(--aurora-border)] bg-[var(--aurora-surface)] shadow-xs flex items-center justify-between"
              >
                <div>
                  <div className="text-sm font-semibold text-[var(--aurora-fg1)]">{str(a.title)}</div>
                  <div className="text-xs text-[var(--aurora-fg4)] font-mono mt-0.5">
                    {statusLabels[str(a.status)] ?? str(a.status)} · /{str(a.slug)}
                  </div>
                </div>
                <Btn variant="ghost" size="sm" disabled={busy !== null} onClick={() => act(str(a.id), () => api.skillAction(str(a.id), "restore"), s.restoredNotice)}>
                  恢复技能
                </Btn>
              </div>
            ))
          ) : (
            <Glass padding={24} radius={18} className="text-center text-xs text-[var(--aurora-fg3)]">
              暂无已归档技能
            </Glass>
          )}
        </div>
      )}

      {/* ─────────────────────────────────────────────────────────────
          5. 设备端生效报告 (Device Sync Matrix)
          ───────────────────────────────────────────────────────────── */}
      {devices.length > 0 && (
        <div className="rounded-3xl p-5 border border-[var(--aurora-border)] bg-[var(--aurora-surface)] shadow-xs">
          <div className="flex items-center gap-2 pb-3 mb-2 border-b border-[var(--aurora-border)]">
            <Icon name="devices" size={15} />
            <span className="font-bold text-xs text-[var(--aurora-fg1)]">各设备技能分发生效状态</span>
          </div>
          <div className="grid grid-cols-1 sm:grid-cols-2 gap-3">
            {devices.map((d, i) => (
              <div key={i} className="p-3 rounded-xl bg-[var(--aurora-surface-solid)] border border-[var(--aurora-border)] flex items-center justify-between text-xs">
                <span className="font-semibold text-[var(--aurora-fg1)] truncate">{str(d.name)}</span>
                <span className="text-[11px] text-[var(--aurora-fg3)] font-mono">{deviceSummary(d)}</span>
              </div>
            ))}
          </div>
        </div>
      )}
    </div>
  );
}
