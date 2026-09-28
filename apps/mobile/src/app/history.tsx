import { router } from "expo-router";
import { useCallback, useEffect, useState } from "react";
import { FlatList, Pressable, Text, View } from "react-native";

import { Loading, Muted, Note } from "../components/ui";
import { describeError } from "../lib/api";
import { shortTime, str } from "../lib/format";
import { useSession } from "../lib/session";
import { useTheme } from "../lib/theme";

/** Past ask conversations; picking one opens it on the ask tab. */
export default function HistoryScreen() {
  const t = useTheme();
  const { api } = useSession();
  const [items, setItems] = useState<Record<string, unknown>[] | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [refreshing, setRefreshing] = useState(false);

  const load = useCallback(async () => {
    try {
      setItems(await api.conversations());
      setError(null);
    } catch (e) {
      setError(describeError(e));
    }
  }, [api]);

  useEffect(() => {
    void load();
  }, [load]);

  return (
    <View style={{ flex: 1, backgroundColor: t.bg }}>
      {error && (
        <View style={{ padding: 16 }}>
          <Note>{error}</Note>
        </View>
      )}
      {!items && !error && <Loading />}
      {items && (
        <FlatList
          data={items}
          keyExtractor={(c) => str(c.id)}
          refreshing={refreshing}
          onRefresh={async () => {
            setRefreshing(true);
            await load();
            setRefreshing(false);
          }}
          ListEmptyComponent={
            <View style={{ padding: 24 }}>
              <Muted>还没有对话。</Muted>
            </View>
          }
          renderItem={({ item }) => (
            <Pressable
              onPress={() => router.dismissTo({ pathname: "/", params: { id: str(item.id) } })}
              style={({ pressed }) => ({ paddingHorizontal: 16, paddingVertical: 12, borderBottomWidth: 1, borderBottomColor: t.border, backgroundColor: pressed ? t.surfaceMute : t.bg })}
            >
              <Text style={{ fontSize: 15, color: t.fg1 }} numberOfLines={2}>
                {str(item.title) || "未命名对话"}
              </Text>
              <Text style={{ fontSize: 12, color: t.fg3, marginTop: 3 }}>
                {shortTime(item.updated_at ?? item.created_at)} · {Number(item.message_count ?? 0)} 条消息
              </Text>
            </Pressable>
          )}
        />
      )}
    </View>
  );
}
