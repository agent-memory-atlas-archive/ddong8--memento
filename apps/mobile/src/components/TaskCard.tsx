import { mergeTaskEvent, steerNote, taskRunSummary, taskToolLabel, type TaskEvent, type TaskResult } from "@memento/core";
import * as Clipboard from "expo-clipboard";
import { useState } from "react";
import { Pressable, Text, TextInput, View } from "react-native";

import { describeError } from "../lib/api";
import { str } from "../lib/format";
import { useSession } from "../lib/session";
import { mono, radius, useTheme } from "../lib/theme";
import { Icon, type IconName } from "./Icon";
import { Chip } from "./ui";

export interface ToolCall {
  id?: string;
  name: string;
  args?: Record<string, unknown>;
  device_name?: string;
  result?: TaskResult;
}

export { mergeTaskEvent };

const RUNNING = new Set(["queued", "running", "still_running"]);

function toolIcon(name?: string): IconName {
  switch (name) {
    case "Bash":
    case "BashOutput":
    case "Shell":
      return "terminal";
    case "Read":
      return "book";
    case "Write":
    case "Edit":
    case "MultiEdit":
    case "NotebookEdit":
      return "edit";
    case "Grep":
    case "Glob":
    case "WebSearch":
      return "search";
    case "WebFetch":
      return "link";
    case "Task":
    case "Agent":
      return "layers";
    default:
      return "cube";
  }
}

/** The steps of a structured agent run, newest last; the last 6 unless expanded. */
function Timeline({ events, running }: { events: TaskEvent[]; running: boolean }) {
  const t = useTheme();
  const [all, setAll] = useState(false);
  const [open, setOpen] = useState<string | null>(null);
  const rows = events.filter((e) => e.kind !== "usage" && e.kind !== "session");
  const hidden = !all && rows.length > 6 ? rows.length - 6 : 0;
  const kept = [...events].reverse().find((e) => e.kind === "worktree" && e.status === "kept");
  const line = (icon: IconName, text: string, note?: string | null, color = t.fg3) => (
    <View style={{ flexDirection: "row", gap: 8, paddingVertical: 4 }}>
      <View style={{ paddingTop: 2 }}>
        <Icon name={icon} size={13} color={color} />
      </View>
      <Text style={{ flex: 1, fontSize: 13, lineHeight: 19, color: t.fg2 }}>
        {text}
        {note ? <Text style={{ color: t.fg3 }}>{`  ${note}`}</Text> : null}
      </Text>
    </View>
  );
  return (
    <View style={{ backgroundColor: t.surfaceMute, borderRadius: radius.control, padding: 10, marginTop: 10 }}>
      <View style={{ flexDirection: "row", alignItems: "center", gap: 8 }}>
        <Text style={{ fontSize: 12, fontWeight: "600", color: t.fg2 }}>过程</Text>
        <Text style={{ flex: 1, fontSize: 12, color: t.fg3 }} numberOfLines={1}>
          {taskRunSummary(events)}
        </Text>
        {rows.length > 6 && (
          <Pressable onPress={() => setAll((v) => !v)}>
            <Text style={{ fontSize: 12, color: t.accent }}>{all ? "只看最近" : `全部 ${rows.length} 条`}</Text>
          </Pressable>
        )}
      </View>
      {hidden > 0 && <Text style={{ fontSize: 11.5, color: t.fg4, marginTop: 4 }}>… 前面还有 {hidden} 条</Text>}
      {rows.slice(hidden).map((e, i) => {
        if (e.kind === "tool") {
          const id = e.id ?? String(i);
          const isOpen = open === id && !!e.output;
          return (
            <Pressable key={id} onPress={() => e.output && setOpen(isOpen ? null : id)}>
              <View style={{ flexDirection: "row", alignItems: "center", gap: 8, paddingVertical: 4 }}>
                <Icon name={toolIcon(e.name)} size={13} color={t.fg3} />
                <Text style={{ fontSize: 13, color: t.fg2 }}>{taskToolLabel(e.name)}</Text>
                <Text style={{ flex: 1, fontSize: 12, fontFamily: mono, color: t.fg1 }} numberOfLines={1}>
                  {e.detail ?? ""}
                </Text>
                {e.status === "failed" ? (
                  <Icon name="close" size={13} color={t.danger} />
                ) : e.status === "running" ? (
                  <Text style={{ fontSize: 12, color: running ? t.accent : t.fg4 }}>•••</Text>
                ) : (
                  <Icon name="check" size={13} color={t.success} />
                )}
              </View>
              {isOpen && (
                <Text selectable style={{ fontFamily: mono, fontSize: 11.5, color: t.fg2, backgroundColor: t.surface, padding: 8, borderRadius: 6, marginLeft: 21 }}>
                  {e.output}
                </Text>
              )}
            </Pressable>
          );
        }
        if (e.kind === "steer") return <View key={i}>{line("message", `你补充：${e.text}`, steerNote(e.status), e.status === "sent" ? t.accent : t.warn)}</View>;
        if (e.kind === "worktree") {
          if (e.status === "created") return <View key={i}>{line("layers", `在独立分支 ${e.branch ?? ""} 上运行`)}</View>;
          if (e.status === "removed") return <View key={i}>{line("layers", "没有改动，已清理独立分支")}</View>;
          if (e.status === "skipped") return <View key={i}>{line("layers", "没用独立分支", e.reason, t.warn)}</View>;
          return null;
        }
        if (e.kind === "error") return <View key={i}>{line("close", e.message, null, t.danger)}</View>;
        return null;
      })}
      {kept?.kind === "worktree" && (
        <View style={{ backgroundColor: t.accentSoft, borderRadius: 8, padding: 10, marginTop: 8 }}>
          <Text style={{ fontSize: 13, fontWeight: "600", color: t.fg1 }}>
            改动留在独立分支 {kept.branch}：{kept.file_count ?? 0} 个文件{kept.commits ? `，${kept.commits} 个提交` : "（还没提交）"}
          </Text>
          <Pressable onPress={() => void Clipboard.setStringAsync(`git merge ${kept.branch}`)} style={{ marginTop: 6, flexDirection: "row", gap: 6, alignItems: "center" }}>
            <Text style={{ flex: 1, fontSize: 12, color: t.fg2 }}>看过没问题就在原仓库合并：git merge {kept.branch}</Text>
            <Icon name="copy" size={13} color={t.accent} />
          </Pressable>
        </View>
      )}
    </View>
  );
}

/** A follow-up for a running Claude task; it reads it at its next step. */
function SteerBox({ taskId }: { taskId: string }) {
  const t = useTheme();
  const { api } = useSession();
  const [text, setText] = useState("");
  const [sending, setSending] = useState(false);
  const [note, setNote] = useState<string | null>(null);
  const send = async () => {
    const value = text.trim();
    if (!value || sending) return;
    setSending(true);
    setNote(null);
    try {
      const res = await api.sendTaskInput(taskId, value);
      if (res.ok) setText("");
      else setNote("没送达：任务可能已经结束，或设备刚断开");
    } catch (e) {
      setNote(describeError(e));
    } finally {
      setSending(false);
    }
  };
  return (
    <View style={{ marginTop: 10 }}>
      <View style={{ flexDirection: "row", gap: 6 }}>
        <TextInput
          value={text}
          onChangeText={setText}
          onSubmitEditing={send}
          placeholder="补充一句，它会在下一步读到"
          placeholderTextColor={t.fg4}
          style={{ flex: 1, fontSize: 14, color: t.fg1, backgroundColor: t.surfaceMute, borderRadius: radius.control, paddingHorizontal: 10, paddingVertical: 8 }}
        />
        <Pressable
          onPress={send}
          disabled={sending || !text.trim()}
          style={{ width: 38, borderRadius: radius.control, alignItems: "center", justifyContent: "center", backgroundColor: t.accentSoft, opacity: sending || !text.trim() ? 0.5 : 1 }}
        >
          <Icon name="arrow_up" size={16} color={t.accent} />
        </Pressable>
      </View>
      {note && <Text style={{ fontSize: 12, color: t.warn, marginTop: 4 }}>{note}</Text>}
    </View>
  );
}

/** One tool call of an ask run: a device task with its output, steps and follow-ups. */
export function TaskCard({ call }: { call: ToolCall }) {
  const t = useTheme();
  const { api } = useSession();
  const [expanded, setExpanded] = useState(false);
  const r = call.result;
  const args = call.args ?? {};
  const binary = str(args.binary).toLowerCase();
  const status = str(r?.status) || "queued";
  const running = !r || RUNNING.has(status);
  const events = r?.events ?? [];
  const label = binary.includes("claude") ? "Claude Code" : binary.includes("codex") ? "Codex" : binary.includes("agy") || binary.includes("antigravity") ? "Antigravity" : call.name === "run_on_device" ? "Shell" : call.name;
  const device = r?.device_name || call.device_name || str(args.device_id);
  const prompt = str(args.prompt || args.command);
  const output = [r?.stdout, r?.stderr ? `[stderr]\n${r.stderr}` : "", r?.error && !r?.stderr ? r.error : ""].filter(Boolean).join("\n\n");
  const tone = running ? "accent" : status === "succeeded" ? "success" : "danger";
  const statusText = running ? (status === "queued" ? "排队中" : "运行中") : status === "succeeded" ? "完成" : status === "timeout" ? "超时" : status === "cancelled" ? "已取消" : "失败";

  if (call.name !== "run_on_device" && !r?.task_id) {
    return (
      <View style={{ flexDirection: "row", gap: 6, alignItems: "center", paddingVertical: 4 }}>
        <Icon name="zap" size={13} color={t.fg3} />
        <Text style={{ fontSize: 13, color: t.fg3 }}>{call.name}</Text>
      </View>
    );
  }

  return (
    <View style={{ borderWidth: 1, borderColor: running ? t.accent : t.border, borderRadius: radius.card, padding: 12, marginVertical: 6, backgroundColor: t.surface }}>
      <View style={{ flexDirection: "row", alignItems: "center", gap: 8 }}>
        <Icon name="terminal" size={15} color={t.accent} />
        <Text style={{ fontSize: 14, fontWeight: "600", color: t.fg1 }}>{label}</Text>
        {!!device && (
          <Text style={{ flex: 1, fontSize: 12, color: t.fg3 }} numberOfLines={1}>
            · {device}
          </Text>
        )}
        {!device && <View style={{ flex: 1 }} />}
        <Chip tone={tone}>{statusText}</Chip>
      </View>
      {!!prompt && (
        <Text style={{ fontSize: 13, color: t.fg2, marginTop: 8, lineHeight: 19 }} numberOfLines={expanded ? undefined : 3}>
          {prompt}
        </Text>
      )}
      {events.length > 0 && <Timeline events={events} running={running} />}
      {running && binary.includes("claude") && !!r?.task_id && events.length > 0 && <SteerBox taskId={r.task_id} />}
      {!!output && (
        <Pressable onPress={() => setExpanded((v) => !v)}>
          <Text
            selectable
            numberOfLines={expanded ? undefined : 8}
            style={{ fontFamily: mono, fontSize: 12, lineHeight: 18, color: t.fg2, backgroundColor: t.surfaceMute, borderRadius: 8, padding: 10, marginTop: 10 }}
          >
            {output}
          </Text>
          <Text style={{ fontSize: 12, color: t.accent, marginTop: 4 }}>{expanded ? "收起" : "展开全部输出"}</Text>
        </Pressable>
      )}
      {running && !!r?.task_id && (
        <View style={{ flexDirection: "row", justifyContent: "flex-end", marginTop: 8 }}>
          <Pressable onPress={() => void api.cancelTask(r.task_id!).catch(() => {})}>
            <Text style={{ fontSize: 12.5, color: t.danger }}>停止任务</Text>
          </Pressable>
        </View>
      )}
    </View>
  );
}
