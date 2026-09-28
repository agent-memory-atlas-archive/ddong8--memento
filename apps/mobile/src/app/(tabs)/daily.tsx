import { useCallback, useEffect, useState } from "react";
import { Pressable, Text, TextInput, View } from "react-native";

import { Icon } from "../../components/Icon";
import { Markdown } from "../../components/Markdown";
import { Screen } from "../../components/Screen";
import { Button, Card, Loading, Muted, Note, Title } from "../../components/ui";
import { describeError } from "../../lib/api";
import { list, num, obj, str, today } from "../../lib/format";
import { useSession } from "../../lib/session";
import { radius, useTheme } from "../../lib/theme";

type Todo = Record<string, unknown>;

function dueLabel(due: string): { text: string; overdue: boolean; soon: boolean } {
  const d = new Date(`${due}T00:00:00`);
  const now = new Date();
  const days = Math.round((d.getTime() - new Date(now.getFullYear(), now.getMonth(), now.getDate()).getTime()) / 86_400_000);
  if (days < 0) return { text: `逾期 ${-days} 天`, overdue: true, soon: false };
  if (days === 0) return { text: "今天到期", overdue: false, soon: true };
  return { text: `${d.getMonth() + 1}-${d.getDate()} 到期`, overdue: false, soon: days <= 3 };
}

/** Todos first, then what happened today. */
export default function DailyScreen() {
  const t = useTheme();
  const { api } = useSession();
  const [todos, setTodos] = useState<Todo[] | null>(null);
  const [daily, setDaily] = useState<Record<string, unknown> | null>(null);
  const [date, setDate] = useState(today());
  const [dates, setDates] = useState<string[]>([]);
  const [newTodo, setNewTodo] = useState("");
  const [busy, setBusy] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);

  const load = useCallback(async () => {
    try {
      const [td, dd, days] = await Promise.all([api.todos().catch(() => ({ open: [] })), api.daily(date), api.dailyDates(14).catch(() => [])]);
      setTodos(list(td.open));
      setDaily(dd);
      setDates(list(days).map((d) => str(d.date)).filter(Boolean));
      setError(null);
    } catch (e) {
      setError(describeError(e));
    }
  }, [api, date]);

  useEffect(() => {
    void load();
  }, [load]);

  const update = async (todo: Todo, fields: Record<string, unknown>) => {
    setBusy(str(todo.id));
    try {
      await api.updateTodo(str(todo.id), fields);
      await load();
    } catch (e) {
      setError(describeError(e));
    } finally {
      setBusy(null);
    }
  };

  const add = async () => {
    const title = newTodo.trim();
    if (!title) return;
    setBusy("add");
    try {
      await api.addTodo(title);
      setNewTodo("");
      await load();
    } catch (e) {
      setError(describeError(e));
    } finally {
      setBusy(null);
    }
  };

  const overview = obj(daily?.overview);
  const conversations = list(overview.conversations);
  const summaries = list(daily?.summaries);
  const toolStats = Object.entries(obj(overview.tool_stats)).sort((a, b) => num(b[1]) - num(a[1]));

  return (
    <Screen title="日报" onRefresh={load}>
      {error && <Note>{error}</Note>}
      <Card>
        <Title trailing={todos ? `${todos.length} 条` : undefined}>待办</Title>
        {!todos && <Loading />}
        {todos?.length === 0 && <Muted>没有待办。你在 AI 工具里说「明天再弄」「记一下…」时会自动出现在这里。</Muted>}
        {todos?.map((todo) => {
          const due = str(todo.due);
          const d = due ? dueLabel(due) : null;
          return (
            <View key={str(todo.id)} style={{ flexDirection: "row", gap: 10, paddingVertical: 8, alignItems: "flex-start" }}>
              <Pressable
                onPress={() => update(todo, { status: "done" })}
                disabled={busy !== null}
                hitSlop={8}
                style={{ width: 22, height: 22, borderRadius: 6, borderWidth: 1.5, borderColor: t.borderStrong, marginTop: 1, alignItems: "center", justifyContent: "center" }}
              >
                {busy === todo.id && <Icon name="check" size={14} color={t.accent} />}
              </Pressable>
              <View style={{ flex: 1 }}>
                <Text style={{ fontSize: 14.5, color: t.fg1, lineHeight: 20 }}>{str(todo.title)}</Text>
                <Text style={{ fontSize: 12, color: t.fg3, marginTop: 2 }}>
                  {d && <Text style={{ color: d.overdue ? t.danger : d.soon ? t.warn : t.fg3 }}>{d.text} · </Text>}
                  {str(todo.project) || (todo.source === "voice" ? "你说的" : todo.source === "session" ? "会话遗留" : "AI 记的")}
                </Text>
              </View>
              <Pressable onPress={() => update(todo, { status: "dropped" })} disabled={busy !== null} hitSlop={8}>
                <Icon name="close" size={15} color={t.fg4} />
              </Pressable>
            </View>
          );
        })}
        <View style={{ flexDirection: "row", gap: 8, marginTop: 8 }}>
          <TextInput
            value={newTodo}
            onChangeText={setNewTodo}
            onSubmitEditing={add}
            placeholder="新建待办"
            placeholderTextColor={t.fg4}
            style={{ flex: 1, fontSize: 14, color: t.fg1, backgroundColor: t.surfaceMute, borderRadius: radius.control, paddingHorizontal: 10, paddingVertical: 8 }}
          />
          <Button small icon="plus" busy={busy === "add"} disabled={!newTodo.trim()} onPress={add} />
        </View>
      </Card>

      {dates.length > 0 && (
        <View style={{ flexDirection: "row", flexWrap: "wrap", gap: 6, marginBottom: 12 }}>
          {[today(), ...dates.filter((d) => d !== today())].slice(0, 8).map((d) => (
            <Pressable
              key={d}
              onPress={() => setDate(d)}
              style={{ paddingHorizontal: 10, paddingVertical: 5, borderRadius: 999, borderWidth: 1, borderColor: d === date ? t.accent : t.border, backgroundColor: d === date ? t.accentSoft : t.surface }}
            >
              <Text style={{ fontSize: 12.5, color: d === date ? t.accent : t.fg2 }}>{d === today() ? "今天" : d.slice(5)}</Text>
            </Pressable>
          ))}
        </View>
      )}

      <Card>
        <Title trailing={daily ? `${num(daily.total_messages)} 条消息` : undefined}>{date === today() ? "今天" : date}</Title>
        {!daily && <Loading />}
        {daily && num(daily.total_messages) === 0 && <Muted>这一天没有记录到活动。</Muted>}
        {toolStats.length > 0 && (
          <Text style={{ fontSize: 13, color: t.fg2, marginBottom: 8 }}>{toolStats.map(([tool, n]) => `${tool} ${num(n)}`).join(" · ")}</Text>
        )}
        {summaries.map((s, i) => (
          <View key={i} style={{ marginBottom: 8 }}>
            <Markdown>{`### ${str(s.title) || "AI 小结"}\n${str(s.summary)}`}</Markdown>
          </View>
        ))}
        {conversations.slice(0, 12).map((c, i) => (
          <View key={i} style={{ flexDirection: "row", gap: 8, paddingVertical: 5 }}>
            <Text style={{ fontSize: 12, color: t.fg4, width: 76 }} numberOfLines={1}>
              {str(c.tool_id)}
            </Text>
            <Text style={{ flex: 1, fontSize: 13.5, color: t.fg1 }} numberOfLines={1}>
              {str(c.title) || str(c.id).slice(0, 8)}
            </Text>
            <Text style={{ fontSize: 12, color: t.fg3 }}>
              {num(c.user_messages)}↑ {num(c.assistant_messages)}↓
            </Text>
          </View>
        ))}
      </Card>
    </Screen>
  );
}
