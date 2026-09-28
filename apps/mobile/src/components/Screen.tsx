import { useCallback, useState, type ReactNode } from "react";
import { RefreshControl, ScrollView, Text, View } from "react-native";
import { SafeAreaView } from "react-native-safe-area-context";

import { useTheme } from "../lib/theme";

/** A tab's page: large title, pull to refresh, and a readable column on tablets. */
export function Screen({ title, right, onRefresh, children }: { title: string; right?: ReactNode; onRefresh?: () => Promise<unknown>; children: ReactNode }) {
  const t = useTheme();
  const [refreshing, setRefreshing] = useState(false);
  const refresh = useCallback(async () => {
    if (!onRefresh) return;
    setRefreshing(true);
    try {
      await onRefresh();
    } finally {
      setRefreshing(false);
    }
  }, [onRefresh]);
  return (
    <SafeAreaView style={{ flex: 1, backgroundColor: t.bg }} edges={["top"]}>
      <ScrollView
        contentContainerStyle={{ padding: 16, paddingBottom: 32, width: "100%", maxWidth: 760, alignSelf: "center" }}
        refreshControl={onRefresh ? <RefreshControl refreshing={refreshing} onRefresh={refresh} tintColor={t.accent} /> : undefined}
        keyboardShouldPersistTaps="handled"
      >
        <View style={{ flexDirection: "row", alignItems: "center", marginBottom: 14 }}>
          <Text style={{ flex: 1, fontSize: 26, fontWeight: "700", color: t.fg1, letterSpacing: -0.5 }}>{title}</Text>
          {right}
        </View>
        {children}
      </ScrollView>
    </SafeAreaView>
  );
}
