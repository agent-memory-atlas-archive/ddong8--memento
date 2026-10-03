"use client";

import { useCallback, useEffect, useRef, useState, type CSSProperties } from "react";
import { api } from "@/lib/api-client";
import { fmt, useI18n } from "@/lib/i18n";
import { Btn, Chip, Glass, TopBar } from "@/components/aurora/primitives";
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
  padding: "8px 10px",
  borderRadius: 10,
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
    <div style={{ marginTop: 10 }}>
      {label(s.fieldTitle)}
      <input value={title} onChange={(e) => setTitle(e.target.value)} style={field} />
      {label(s.fieldSlug, s.fieldSlugHint)}
      <input value={slug} onChange={(e) => setSlug(e.target.value)} style={{ ...field, ...mono }} />
      {label(s.fieldDescription, s.fieldDescriptionHint)}
      <textarea value={description} onChange={(e) => setDescription(e.target.value)} rows={3} style={{ ...field, resize: "vertical" }} />
      {label(s.fieldBody)}
      <textarea value={body} onChange={(e) => setBody(e.target.value)} rows={16} style={{ ...field, ...mono, lineHeight: 1.55, resize: "vertical" }} />
      <div style={{ display: "flex", gap: 8, justifyContent: "flex-end", marginTop: 10, flexWrap: "wrap" }}>
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
  const [showArchived, setShowArchived] = useState(false);
  const [showReviews, setShowReviews] = useState(false);
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

  const renderSkill = (skill: Obj) => {
    const id = str(skill.id);
    const status = str(skill.status) || "draft";
    const disabled = busy !== null;
    const update = skill.pending_update ? obj(skill.pending_update) : null;
    const evidence = list(skill.evidence);
    const meta = [
      str(skill.project),
      status === "published" ? `v${str(skill.version)}` : "",
      fmt(s.seenTimes, { n: num(skill.times_seen) || 1 }),
      skill.last_seen_at ? fmt(s.lastSeen, { at: time(skill.last_seen_at) }) : "",
      skill.edited_by_user === true ? s.editedByYou : "",
    ].filter(Boolean);
    return (
      <div key={id} style={{ padding: "14px 0", borderTop: "1px solid var(--aurora-border)" }}>
        <div style={{ fontSize: 15, fontWeight: 600, color: "var(--aurora-fg1)" }}>{str(skill.title)}</div>
        <div style={{ fontSize: 12, color: "var(--aurora-fg3)", marginTop: 3, ...mono }}>
          /{str(skill.slug)} · {meta.join(" · ")}
        </div>
        <p style={{ margin: "8px 0 0", fontSize: 13.5, lineHeight: 1.55, color: "var(--aurora-fg2)" }}>{str(skill.description)}</p>

        {update && (
          <div style={{ marginTop: 10, padding: 10, borderRadius: 10, background: "rgba(217,119,6,0.08)", border: "1px solid rgba(217,119,6,0.3)" }}>
            <div style={{ fontSize: 12.5, color: "#B45309", lineHeight: 1.45 }}>{fmt(s.updateFound, { reason: str(update.reason) })}</div>
            {showUpdate === id && (
              <div style={{ marginTop: 8 }}>
                <p style={{ margin: "0 0 8px", fontSize: 13, color: "var(--aurora-fg2)" }}>{str(update.description)}</p>
                <div className="prose prose-sm max-w-none">
                  <MarkdownViewer content={str(update.body)} />
                </div>
              </div>
            )}
            <div style={{ display: "flex", gap: 6, justifyContent: "flex-end", marginTop: 6, flexWrap: "wrap" }}>
              <Btn variant="ghost" size="sm" disabled={disabled} onClick={() => act(id, () => api.skillAction(id, "update/discard"))}>
                {s.no}
              </Btn>
              <Btn variant="glass" size="sm" onClick={() => setShowUpdate(showUpdate === id ? null : id)}>
                {showUpdate === id ? s.hide : s.look}
              </Btn>
              <Btn size="sm" disabled={disabled} onClick={() => act(id, () => api.skillAction(id, "update/apply"), s.updateApplied)}>
                {s.apply}
              </Btn>
            </div>
          </div>
        )}

        {editing === id ? (
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
        ) : (
          <>
            <button
              type="button"
              onClick={() => toggle(id)}
              style={{ display: "inline-flex", alignItems: "center", gap: 4, marginTop: 8, background: "none", border: 0, padding: 0, cursor: "pointer", color: "var(--aurora-accent)", fontSize: 12.5 }}
            >
              <Icon name={expanded.has(id) ? "minus" : "plus"} size={12} />
              {expanded.has(id) ? s.hideSteps : s.showSteps}
            </button>
            {expanded.has(id) && (
              <div style={{ marginTop: 8 }}>
                <div className="prose prose-sm max-w-none" style={{ padding: 12, borderRadius: 10, background: "var(--aurora-surface-mute)" }}>
                  <MarkdownViewer content={str(skill.body)} />
                </div>
                {evidence
                  .slice(-3)
                  .reverse()
                  .map((e, i) => (
                    <div key={i} style={{ fontSize: 12, color: "var(--aurora-fg3)", marginTop: 4, whiteSpace: "nowrap", overflow: "hidden", textOverflow: "ellipsis" }}>
                      {fmt(s.fromSession, { title: str(e.title), tool: str(e.tool_id), at: time(e.at) })}
                    </div>
                  ))}
              </div>
            )}
            <div style={{ display: "flex", gap: 8, justifyContent: "flex-end", marginTop: 8, flexWrap: "wrap" }}>
              {status === "draft" && (
                <>
                  <Btn variant="ghost" size="sm" disabled={disabled} onClick={() => act(id, () => api.skillAction(id, "dismiss"))}>
                    {s.no}
                  </Btn>
                  <Btn variant="glass" size="sm" icon="edit" disabled={disabled} onClick={() => setEditing(id)}>
                    {s.edit}
                  </Btn>
                  <Btn size="sm" icon="rocket" disabled={disabled} onClick={() => act(id, () => api.publishSkill(id), s.publishedNotice)}>
                    {busy === id ? s.working : s.publish}
                  </Btn>
                </>
              )}
              {status === "published" && (
                <>
                  <Btn variant="ghost" size="sm" disabled={disabled} onClick={() => act(id, () => api.skillAction(id, "retire"), s.retiredNotice)}>
                    {s.retire}
                  </Btn>
                  <Btn variant="glass" size="sm" icon="edit" disabled={disabled} onClick={() => setEditing(id)}>
                    {s.edit}
                  </Btn>
                </>
              )}
            </div>
          </>
        )}
      </div>
    );
  };

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
    const status = obj(d.status);
    if (!status.results) return s.deviceWaiting;
    const c = skillResultCounts(obj(status.results));
    const parts = [
      c.ok ? fmt(s.deviceWritten, { n: c.ok }) : "",
      c.kept ? fmt(s.deviceKept, { n: c.kept }) : "",
      c.skipped ? fmt(s.deviceSkipped, { n: c.skipped }) : "",
      c.error ? fmt(s.deviceErrors, { n: c.error }) : "",
    ].filter(Boolean);
    return `${parts.length ? parts.join(" · ") : s.deviceNoSkills} · ${time(status.reported_at)}`;
  };

  const draftsList = data ? list(data.drafts) : [];
  const publishedList = data ? list(data.published) : [];

  return (
    <div className="w-full max-w-5xl mx-auto pb-16 min-w-0">
      {/* Global Cognitive Compass Navigation */}
      <CognitiveCompass
        currentTab="skills"
        summaryStats={{
          skillsCount: draftsList.length + publishedList.length,
        }}
      />

      <TopBar
        title="技能进化 · 特长与工具箱"
        subtitle="AI 会执行什么 · 从日常会话与任务中提炼 SOP、执行脚本与标准化工作流"
        right={
          <Btn variant="glass" size="sm" icon="refresh" disabled={reviewRunning || busy !== null} onClick={reviewNow}>
            {reviewRunning ? s.reviewing : "自动审查提炼技能"}
          </Btn>
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
      {!data && !error && <p style={{ color: "var(--aurora-fg3)", fontSize: 13 }}>{t.loading}</p>}
      {job?.finished_at != null && !reviewRunning && (
        <p style={{ margin: "-10px 0 14px", fontSize: 12, color: "var(--aurora-fg3)" }}>{fmt(s.lastManualReview, { at: time(job.finished_at) })}</p>
      )}

      {data && (
        <>
          {drafts.length > 0 && (
            <Glass padding="clamp(14px, 3vw, 20px)" radius={18} style={{ marginBottom: 14, border: "1px solid var(--aurora-accent)" }}>
              <div style={{ display: "flex", gap: 8, alignItems: "center" }}>
                <Chip tone="accent">{s.statusDraft}</Chip>
                <span style={{ fontSize: 12, color: "var(--aurora-fg3)" }}>{fmt(s.draftsCaption, { n: drafts.length })}</span>
              </div>
              <div style={{ marginTop: 6 }}>{drafts.map(renderSkill)}</div>
            </Glass>
          )}
          {published.length > 0 && (
            <Glass padding="clamp(14px, 3vw, 20px)" radius={18} style={{ marginBottom: 14 }}>
              <div style={{ display: "flex", gap: 8, alignItems: "center" }}>
                <Chip tone="success">{s.statusPublished}</Chip>
                <span style={{ fontSize: 12, color: "var(--aurora-fg3)" }}>{fmt(s.publishedCaption, { n: published.length })}</span>
              </div>
              <div style={{ marginTop: 6 }}>{published.map(renderSkill)}</div>
            </Glass>
          )}
          {drafts.length === 0 && published.length === 0 && (
            <Glass padding={24} radius={18} style={{ marginBottom: 14, textAlign: "center" }}>
              <Icon name="zap" size={26} style={{ color: "var(--aurora-fg3)" }} />
              <div style={{ fontSize: 14, fontWeight: 600, color: "var(--aurora-fg1)", marginTop: 8 }}>{s.emptyTitle}</div>
              <p style={{ margin: "4px 0 0", fontSize: 12.5, color: "var(--aurora-fg3)", lineHeight: 1.55 }}>{s.emptyHint}</p>
            </Glass>
          )}

          {archived.length > 0 && (
            <Glass padding="12px 18px" radius={18} style={{ marginBottom: 14 }}>
              <button type="button" onClick={() => setShowArchived((v) => !v)} style={{ display: "flex", width: "100%", alignItems: "center", background: "none", border: 0, padding: 0, cursor: "pointer", color: "var(--aurora-fg2)", fontSize: 13.5 }}>
                <span style={{ flex: 1, textAlign: "left" }}>{fmt(s.archivedTitle, { n: archived.length })}</span>
                <Icon name={showArchived ? "minus" : "plus"} size={14} />
              </button>
              {showArchived &&
                archived.map((a) => (
                  <div key={str(a.id)} style={{ display: "flex", alignItems: "center", gap: 8, padding: "8px 0", borderTop: "1px solid var(--aurora-border)", marginTop: 8 }}>
                    <div style={{ flex: 1, minWidth: 0 }}>
                      <div style={{ fontSize: 13.5, color: "var(--aurora-fg1)" }}>{str(a.title)}</div>
                      <div style={{ fontSize: 12, color: "var(--aurora-fg3)" }}>
                        {statusLabels[str(a.status)] ?? str(a.status)} · /{str(a.slug)}
                      </div>
                    </div>
                    <Btn variant="ghost" size="sm" disabled={busy !== null} onClick={() => act(str(a.id), () => api.skillAction(str(a.id), "restore"), s.restoredNotice)}>
                      {s.restore}
                    </Btn>
                  </div>
                ))}
            </Glass>
          )}

          <Glass padding="12px 18px" radius={18} style={{ marginBottom: 14 }}>
            <button type="button" onClick={() => setShowReviews((v) => !v)} style={{ display: "flex", width: "100%", alignItems: "center", background: "none", border: 0, padding: 0, cursor: "pointer", textAlign: "left" }}>
              <span style={{ flex: 1 }}>
                <span style={{ display: "block", fontSize: 13.5, color: "var(--aurora-fg2)" }}>{s.reviewsTitle}</span>
                <span style={{ display: "block", fontSize: 12, color: "var(--aurora-fg3)", marginTop: 2 }}>
                  {reviewList.length === 0
                    ? s.noReviews
                    : fmt(s.reviewStats, { n: num(stats.sessions), done: num(outcomes.done), partial: num(outcomes.partial), failed: num(outcomes.failed) })}
                </span>
              </span>
              <Icon name={showReviews ? "minus" : "plus"} size={14} style={{ color: "var(--aurora-fg3)" }} />
            </button>
            {showReviews &&
              reviewList.slice(0, 20).map((r, i) => (
                <div key={i} style={{ padding: "10px 0", borderTop: "1px solid var(--aurora-border)", marginTop: i === 0 ? 10 : 0 }}>
                  <div style={{ display: "flex", alignItems: "center", gap: 8 }}>
                    <Chip tone={outcomeTone(str(r.outcome))}>{outcomeLabels[str(r.outcome)] ?? str(r.outcome)}</Chip>
                    <span style={{ flex: 1, minWidth: 0, fontSize: 13, color: "var(--aurora-fg1)", whiteSpace: "nowrap", overflow: "hidden", textOverflow: "ellipsis" }}>{str(r.title)}</span>
                    <span style={{ fontSize: 11.5, color: "var(--aurora-fg3)" }}>{time(r.reviewed_at)}</span>
                  </div>
                  {str(r.summary) && <p style={{ margin: "4px 0 0", fontSize: 12.5, color: "var(--aurora-fg2)", lineHeight: 1.45 }}>{str(r.summary)}</p>}
                  <div style={{ fontSize: 12, color: "var(--aurora-fg3)", marginTop: 2 }}>{fmt(s.learned, { what: learned(obj(r.result)) })}</div>
                </div>
              ))}
          </Glass>

          {devices.length > 0 && (
            <Glass padding="clamp(14px, 3vw, 20px)" radius={18}>
              <div style={{ fontSize: 13.5, fontWeight: 600, color: "var(--aurora-fg1)", marginBottom: 8 }}>{s.devicesTitle}</div>
              {devices.map((d, i) => (
                <div key={i} style={{ display: "flex", gap: 12, padding: "5px 0", fontSize: 13 }}>
                  <span style={{ flex: 1, minWidth: 0, color: "var(--aurora-fg2)", whiteSpace: "nowrap", overflow: "hidden", textOverflow: "ellipsis" }}>{str(d.name)}</span>
                  <span style={{ fontSize: 12, color: "var(--aurora-fg3)", textAlign: "right" }}>{deviceSummary(d)}</span>
                </div>
              ))}
            </Glass>
          )}
        </>
      )}
    </div>
  );
}
