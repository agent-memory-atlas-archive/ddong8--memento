import { useCallback, useEffect, useState } from "react";
import { Pressable, Text, TextInput, View } from "react-native";

import { Icon } from "../../components/Icon";
import { Markdown } from "../../components/Markdown";
import { Screen } from "../../components/Screen";
import { Button, Card, Chip, Loading, Muted, Note, Title } from "../../components/ui";
import { describeError } from "../../lib/api";
import { list, shortTime, str } from "../../lib/format";
import { useSession } from "../../lib/session";
import { radius, useTheme } from "../../lib/theme";

type Hit = Record<string, unknown>;

/** Search everything collected, see the rules it learned, and confirm new corrections. */
export default function MemoryScreen() {
  const t = useTheme();
  const { api } = useSession();
  const [query, setQuery] = useState("");
  const [hits, setHits] = useState<Hit[] | null>(null);
  const [searching, setSearching] = useState(false);
  const [core, setCore] = useState<string | null>(null);
  const [pending, setPending] = useState<Hit[]>([]);
  const [open, setOpen] = useState<{ id: string; content: string } | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState<string | null>(null);

  const load = useCallback(async () => {
    try {
      const [md, corr] = await Promise.all([api.coreMarkdown(), api.corrections().catch(() => ({}) as Hit)]);
      setCore(str(md.markdown));
      setPending(list(corr.pending));
      setError(null);
    } catch (e) {
      setError(describeError(e));
    }
  }, [api]);

  useEffect(() => {
    void load();
  }, [load]);

  const search = async () => {
    const q = query.trim();
    if (!q) return;
    setSearching(true);
    setOpen(null);
    try {
      const sem = await api.semantic(q).catch(() => ({ results: [] }) as Hit);
      let results = list(sem.results);
      if (!results.length) results = list((await api.search(q)).results);
      setHits(results);
    } catch (e) {
      setError(describeError(e));
    } finally {
      setSearching(false);
    }
  };

  const openDoc = async (id: string) => {
    if (open?.id === id) return setOpen(null);
    try {
      const doc = await api.document(id);
      setOpen({ id, content: str(doc.content).slice(0, 20_000) });
    } catch (e) {
      setError(describeError(e));
    }
  };

  const decide = async (id: string, accept: boolean) => {
    setBusy(id);
    try {
      if (accept) await api.acceptCorrection(id);
      else await api.dismissCorrection(id);
      await load();
    } catch (e) {
      setError(describeError(e));
    } finally {
      setBusy(null);
    }
  };

  return (
    <Screen title="记忆" onRefresh={load}>
      {error && <Note>{error}</Note>}
      <View style={{ flexDirection: "row", gap: 8, marginBottom: 12 }}>
        <View style={{ flex: 1, flexDirection: "row", alignItems: "center", gap: 8, backgroundColor: t.surface, borderRadius: radius.control, borderWidth: 1, borderColor: t.border, paddingHorizontal: 10 }}>
          <Icon name="search" size={16} color={t.fg3} />
          <TextInput
            value={query}
            onChangeText={setQuery}
            onSubmitEditing={search}
            returnKeyType="search"
            placeholder="搜对话、决定、踩过的坑…"
            placeholderTextColor={t.fg4}
            style={{ flex: 1, fontSize: 15, color: t.fg1, paddingVertical: 10 }}
          />
        </View>
        <Button onPress={search} busy={searching} disabled={!query.trim()}>
          搜索
        </Button>
      </View>

      {hits && (
        <Card>
          <Title trailing={`${hits.length} 条`}>搜索结果</Title>
          {hits.length === 0 && <Muted>没有找到相关的记忆。</Muted>}
          {hits.map((h, i) => (
            <Pressable key={str(h.id) || i} onPress={() => h.id && void openDoc(str(h.id))} style={{ paddingVertical: 8, borderTopWidth: i ? 1 : 0, borderTopColor: t.border }}>
              <View style={{ flexDirection: "row", gap: 6, alignItems: "center" }}>
                <Chip>{str(h.tool_id) || "memo"}</Chip>
                <Text style={{ flex: 1, fontSize: 14, fontWeight: "600", color: t.fg1 }} numberOfLines={1}>
                  {str(h.title) || str(h.relative_path) || "未命名"}
                </Text>
                <Text style={{ fontSize: 11.5, color: t.fg4 }}>{shortTime(h.synced_at)}</Text>
              </View>
              {!!str(h.snippet) && (
                <Text style={{ fontSize: 13, color: t.fg2, marginTop: 4, lineHeight: 19 }} numberOfLines={open?.id === h.id ? undefined : 3}>
                  {str(h.snippet)}
                </Text>
              )}
              {open && open.id === h.id && (
                <Text selectable style={{ fontSize: 12.5, color: t.fg2, marginTop: 8, lineHeight: 18, backgroundColor: t.surfaceMute, padding: 10, borderRadius: 8 }}>
                  {open.content}
                </Text>
              )}
            </Pressable>
          ))}
        </Card>
      )}

      {pending.length > 0 && (
        <Card accent>
          <Title trailing={`${pending.length} 条`}>刚学到的</Title>
          <Muted style={{ marginBottom: 6 }}>从你纠正 AI 的话里学到，采纳后写进常驻画像。</Muted>
          {pending.map((p) => (
            <View key={str(p.id)} style={{ paddingVertical: 10, borderTopWidth: 1, borderTopColor: t.border }}>
              <Text style={{ fontSize: 14.5, color: t.fg1, lineHeight: 21 }}>{str(p.statement)}</Text>
              <Text style={{ fontSize: 12, color: t.fg3, marginTop: 2 }}>你说过 {Number(p.times ?? 1)} 次</Text>
              <View style={{ flexDirection: "row", gap: 8, justifyContent: "flex-end", marginTop: 8 }}>
                <Button small variant="ghost" disabled={busy !== null} onPress={() => decide(str(p.id), false)}>
                  忽略
                </Button>
                <Button small icon="check" busy={busy === p.id} disabled={busy !== null} onPress={() => decide(str(p.id), true)}>
                  采纳
                </Button>
              </View>
            </View>
          ))}
        </Card>
      )}

      <Card>
        <Title>长期准则</Title>
        {core === null ? <Loading /> : core ? <Markdown>{core}</Markdown> : <Muted>还没有沉淀下来的准则，夜间做梦后会出现在这里。</Muted>}
      </Card>
    </Screen>
  );
}
