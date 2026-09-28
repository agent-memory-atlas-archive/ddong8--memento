import { useCallback, useEffect, useState } from "react";
import { Text, View } from "react-native";

import { Screen } from "../../components/Screen";
import { Card, Chip, Loading, Muted, Note } from "../../components/ui";
import { describeError } from "../../lib/api";
import { shortTime, str } from "../../lib/format";
import { useSession } from "../../lib/session";
import { useTheme } from "../../lib/theme";

/** The computers that collect and run tasks, and whether they're reachable. */
export default function DevicesScreen() {
  const t = useTheme();
  const { api } = useSession();
  const [devices, setDevices] = useState<Record<string, unknown>[] | null>(null);
  const [error, setError] = useState<string | null>(null);

  const load = useCallback(async () => {
    try {
      setDevices(await api.devices());
      setError(null);
    } catch (e) {
      setError(describeError(e));
    }
  }, [api]);

  useEffect(() => {
    void load();
  }, [load]);

  return (
    <Screen title="设备" onRefresh={load}>
      {error && <Note>{error}</Note>}
      {!devices && !error && <Loading />}
      {devices?.length === 0 && <Muted>还没有设备。在电脑上安装 Memento 桌面端并登录后会出现在这里。</Muted>}
      {devices?.map((d) => (
        <Card key={str(d.id)}>
          <View style={{ flexDirection: "row", alignItems: "center", gap: 8 }}>
            <View style={{ width: 8, height: 8, borderRadius: 4, backgroundColor: d.online ? t.success : t.fg4 }} />
            <Text style={{ flex: 1, fontSize: 16, fontWeight: "600", color: t.fg1 }} numberOfLines={1}>
              {str(d.name).replace(/\s*\([^)]*\)\s*$/, "")}
            </Text>
            <Chip tone={d.online ? "success" : "neutral"}>{d.online ? "在线" : "离线"}</Chip>
          </View>
          <Text style={{ fontSize: 12.5, color: t.fg3, marginTop: 6 }}>
            {Number(d.document_count ?? 0).toLocaleString()} 个文件 · 最近心跳 {shortTime(d.last_heartbeat) || "—"}
            {d.collector_version ? ` · ${str(d.collector_version)}` : ""}
          </Text>
          {Array.isArray(d.tools) && d.tools.length > 0 && (
            <View style={{ flexDirection: "row", flexWrap: "wrap", gap: 6, marginTop: 10 }}>
              {(d.tools as unknown[]).map((tool) => (
                <Chip key={str(tool)}>{str(tool)}</Chip>
              ))}
            </View>
          )}
        </Card>
      ))}
    </Screen>
  );
}
