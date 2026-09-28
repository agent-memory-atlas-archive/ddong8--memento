import { AskStream, type AskRequest, type AskStreamEvent } from "@memento/core";
import { randomUUID } from "expo-crypto";
import { router, useLocalSearchParams } from "expo-router";
import { useCallback, useEffect, useRef, useState } from "react";
import { KeyboardAvoidingView, Platform, Pressable, ScrollView, Text, TextInput, View } from "react-native";
import { SafeAreaView } from "react-native-safe-area-context";

import { Icon } from "../../components/Icon";
import { Markdown } from "../../components/Markdown";
import { TaskCard } from "../../components/TaskCard";
import { applyEvent, type Turn } from "../../lib/ask";
import { describeError } from "../../lib/api";
import { list, str } from "../../lib/format";
import { useSession } from "../../lib/session";
import { radius, useTheme } from "../../lib/theme";

type Mode = "ai" | "claude" | "codex" | "shell";
const MODES: { id: Mode; label: string }[] = [
  { id: "ai", label: "AI 编排" },
  { id: "claude", label: "Claude" },
  { id: "codex", label: "Codex" },
  { id: "shell", label: "Shell" },
];

function Pill({ label, active, onPress }: { label: string; active: boolean; onPress: () => void }) {
  const t = useTheme();
  return (
    <Pressable
      onPress={onPress}
      style={{
        paddingHorizontal: 11,
        paddingVertical: 6,
        borderRadius: 999,
        borderWidth: 1,
        borderColor: active ? t.accent : t.border,
        backgroundColor: active ? t.accentSoft : t.surface,
      }}
    >
      <Text style={{ fontSize: 13, color: active ? t.accent : t.fg2, fontWeight: active ? "600" : "500" }}>{label}</Text>
    </Pressable>
  );
}

export default function AskScreen() {
  const t = useTheme();
  const { api, server, token } = useSession();
  const params = useLocalSearchParams<{ id?: string }>();
  const [turns, setTurns] = useState<Turn[]>([]);
  const [input, setInput] = useState("");
  const [streaming, setStreaming] = useState(false);
  const [conversationId, setConversationId] = useState<string | null>(null);
  const [devices, setDevices] = useState<{ id: string; name: string; online: boolean }[]>([]);
  const [device, setDevice] = useState("ask_only");
  const [mode, setMode] = useState<Mode>("ai");
  const [worktree, setWorktree] = useState(false);
  const [showOptions, setShowOptions] = useState(false);
  const stream = useRef<AskStream | null>(null);
  const scroll = useRef<ScrollView>(null);

  useEffect(() => {
    api
      .devices()
      .then((rows) => setDevices(rows.map((d) => ({ id: str(d.device_id), name: str(d.name).replace(/\s*\([^)]*\)\s*$/, ""), online: d.online === true }))))
      .catch(() => {});
  }, [api]);

  useEffect(() => () => stream.current?.detach(), []);

  const streamOptions = useCallback(
    () => ({
      baseUrl: server,
      token,
      onEvent: (evt: AskStreamEvent) => {
        if (evt.type === "conversation_id") {
          setConversationId(evt.id);
          return;
        }
        if (evt.type === "done" || evt.type === "ping") return;
        setTurns((prev) => {
          if (!prev.length || prev[prev.length - 1]!.role !== "assistant") return prev;
          const next = [...prev];
          next[next.length - 1] = applyEvent(next[next.length - 1]!, evt);
          return next;
        });
      },
      onRunGone: () => {
        const id = stream.current?.conversation;
        if (id) void api.conversation(id).then((data) => setTurns(list(data.turns) as unknown as Turn[])).catch(() => {});
      },
      onDone: () => setStreaming(false),
    }),
    [api, server, token],
  );

  // Open a conversation from the history list, following it live if it's still running.
  useEffect(() => {
    const id = params.id;
    if (!id || streaming) return;
    void (async () => {
      try {
        stream.current?.detach();
        const data = await api.conversation(id);
        const base = list(data.turns) as unknown as Turn[];
        setConversationId(id);
        if (data.device_id) setDevice(str(data.device_id));
        setTurns(base);
        const run = await api.conversationRun(id).catch(() => null);
        if (run && run.done === false) {
          setTurns([...base, { role: "user", content: str(run.question) }, { role: "assistant", content: "", toolCalls: [] }]);
          setStreaming(true);
          stream.current = AskStream.attach(id, 0, streamOptions());
        }
      } catch (e) {
        setTurns([{ role: "assistant", content: describeError(e), error: true }]);
      }
    })();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [params.id]);

  const send = () => {
    const question = input.trim();
    if (!question || streaming) return;
    const history = turns.filter((x) => !x.error).map((x) => ({ role: x.role, content: x.content }));
    setInput("");
    setTurns((prev) => [...prev, { role: "user", content: question }, { role: "assistant", content: "", toolCalls: [] }]);
    setStreaming(true);
    const agent = device !== "ask_only";
    const body: AskRequest = {
      question,
      request_id: randomUUID(),
      conversation_id: conversationId ?? undefined,
      history,
      device_id: device,
      agent_mode: agent,
      execution_mode: agent ? mode : "ai",
      ...(agent && worktree && (mode === "claude" || mode === "codex") ? { worktree: true } : {}),
    } as AskRequest;
    stream.current = AskStream.ask(body, streamOptions());
  };

  const stop = () => {
    void stream.current?.stop();
    setStreaming(false);
  };

  const newChat = () => {
    stream.current?.detach();
    setStreaming(false);
    setTurns([]);
    setConversationId(null);
    router.setParams({ id: undefined });
  };

  const deviceName = device === "ask_only" ? "仅问记忆" : device === "auto" ? "自动选设备" : devices.find((d) => d.id === device)?.name ?? "设备";
  const agentMode = device !== "ask_only";

  return (
    <SafeAreaView style={{ flex: 1, backgroundColor: t.bg }} edges={["top"]}>
      <KeyboardAvoidingView style={{ flex: 1 }} behavior={Platform.OS === "ios" ? "padding" : undefined} keyboardVerticalOffset={Platform.OS === "ios" ? 80 : 0}>
        <View style={{ flexDirection: "row", alignItems: "center", paddingHorizontal: 16, paddingVertical: 10, gap: 10 }}>
          <Text style={{ flex: 1, fontSize: 22, fontWeight: "700", color: t.fg1 }}>问记忆</Text>
          <Pressable onPress={() => router.push("/history")} hitSlop={8}>
            <Icon name="clock" size={20} color={t.fg2} />
          </Pressable>
          <Pressable onPress={newChat} hitSlop={8}>
            <Icon name="plus" size={22} color={t.fg2} />
          </Pressable>
        </View>

        <ScrollView
          ref={scroll}
          style={{ flex: 1 }}
          contentContainerStyle={{ padding: 16, paddingBottom: 24 }}
          onContentSizeChange={() => scroll.current?.scrollToEnd({ animated: true })}
          keyboardDismissMode="interactive"
        >
          {turns.length === 0 && (
            <View style={{ paddingTop: 48, alignItems: "center", gap: 8 }}>
              <Icon name="sparkles" size={28} color={t.accent} />
              <Text style={{ fontSize: 17, fontWeight: "600", color: t.fg1 }}>问问你的外脑</Text>
              <Text style={{ fontSize: 13.5, color: t.fg3, textAlign: "center", lineHeight: 20, maxWidth: 300 }}>
                它记得你在各个 AI 工具里做过的事。选一台设备还能直接派活给 Claude Code 或 Codex。
              </Text>
            </View>
          )}
          {turns.map((turn, i) =>
            turn.role === "user" ? (
              <View key={i} style={{ alignSelf: "flex-end", maxWidth: "85%", backgroundColor: t.accent, borderRadius: 16, borderBottomRightRadius: 4, paddingHorizontal: 12, paddingVertical: 9, marginVertical: 6 }}>
                <Text selectable style={{ color: t.onAccent, fontSize: 15, lineHeight: 21 }}>
                  {turn.content}
                </Text>
              </View>
            ) : (
              <View key={i} style={{ marginVertical: 6 }}>
                {!!turn.thinking && !turn.content && (
                  <Text style={{ fontSize: 12.5, color: t.fg3, fontStyle: "italic", marginBottom: 4 }} numberOfLines={3}>
                    思考中：{turn.thinking.slice(-160)}
                  </Text>
                )}
                {(turn.toolCalls ?? []).map((call, j) => (
                  <TaskCard key={call.id ?? j} call={call} />
                ))}
                {turn.content ? (
                  turn.error ? (
                    <Text style={{ color: t.danger, fontSize: 14 }}>{turn.content}</Text>
                  ) : (
                    <Markdown>{turn.content}</Markdown>
                  )
                ) : streaming && i === turns.length - 1 && !(turn.toolCalls ?? []).length ? (
                  <Text style={{ color: t.fg3 }}>…</Text>
                ) : null}
                {!!turn.sources?.length && (
                  <Text style={{ fontSize: 12, color: t.fg4, marginTop: 6 }}>参考了 {turn.sources.length} 条记忆</Text>
                )}
              </View>
            ),
          )}
        </ScrollView>

        {showOptions && (
          <View style={{ paddingHorizontal: 16, paddingBottom: 8, gap: 8 }}>
            <ScrollView horizontal showsHorizontalScrollIndicator={false} contentContainerStyle={{ gap: 6 }}>
              <Pill label="仅问记忆" active={device === "ask_only"} onPress={() => setDevice("ask_only")} />
              <Pill label="自动选设备" active={device === "auto"} onPress={() => setDevice("auto")} />
              {devices.map((d) => (
                <Pill key={d.id} label={`${d.online ? "● " : "○ "}${d.name}`} active={device === d.id} onPress={() => setDevice(d.id)} />
              ))}
            </ScrollView>
            {agentMode && (
              <ScrollView horizontal showsHorizontalScrollIndicator={false} contentContainerStyle={{ gap: 6 }}>
                {MODES.map((m) => (
                  <Pill key={m.id} label={m.label} active={mode === m.id} onPress={() => setMode(m.id)} />
                ))}
                {(mode === "claude" || mode === "codex") && <Pill label={worktree ? "独立分支 · 开" : "独立分支 · 关"} active={worktree} onPress={() => setWorktree((v) => !v)} />}
              </ScrollView>
            )}
          </View>
        )}

        <View style={{ flexDirection: "row", alignItems: "flex-end", gap: 8, paddingHorizontal: 12, paddingTop: 8, paddingBottom: 10, borderTopWidth: 1, borderTopColor: t.border, backgroundColor: t.bg }}>
          <Pressable
            onPress={() => setShowOptions((v) => !v)}
            style={{ height: 40, paddingHorizontal: 10, borderRadius: radius.control, backgroundColor: agentMode ? t.accentSoft : t.surfaceMute, justifyContent: "center", maxWidth: 110 }}
          >
            <Text style={{ fontSize: 12.5, color: agentMode ? t.accent : t.fg2, fontWeight: "600" }} numberOfLines={1}>
              {deviceName}
            </Text>
          </Pressable>
          <TextInput
            value={input}
            onChangeText={setInput}
            placeholder={agentMode ? "说说要它做什么…" : "问点什么…"}
            placeholderTextColor={t.fg4}
            multiline
            style={{ flex: 1, maxHeight: 120, minHeight: 40, fontSize: 15, color: t.fg1, backgroundColor: t.surface, borderRadius: radius.control, borderWidth: 1, borderColor: t.border, paddingHorizontal: 12, paddingTop: 10, paddingBottom: 10 }}
          />
          <Pressable
            onPress={streaming ? stop : send}
            disabled={!streaming && !input.trim()}
            style={{ width: 40, height: 40, borderRadius: 20, alignItems: "center", justifyContent: "center", backgroundColor: streaming ? t.dangerSoft : t.accent, opacity: !streaming && !input.trim() ? 0.4 : 1 }}
          >
            <Icon name={streaming ? "stop" : "arrow_up"} size={18} color={streaming ? t.danger : t.onAccent} strokeWidth={2.2} />
          </Pressable>
        </View>
      </KeyboardAvoidingView>
    </SafeAreaView>
  );
}
