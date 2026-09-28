import Constants from "expo-constants";
import { useCallback, useEffect, useState } from "react";
import { Switch, Text, TextInput, View } from "react-native";

import { Screen } from "../../components/Screen";
import { Button, Card, Divider, Loading, Metric, Muted, Note, Row, Title } from "../../components/ui";
import { describeError } from "../../lib/api";
import { list, num, obj, shortTime, str } from "../../lib/format";
import { useSession } from "../../lib/session";
import { radius, useTheme } from "../../lib/theme";

const SWITCHES: { key: string; title: string; hint: string }[] = [
  { key: "notify_risky", title: "危险操作", hint: "agent 执行 git push、rm -rf、改凭据等操作时通知" },
  { key: "notify_task_done", title: "任务完成", hint: "agent 任务结束时，如果你没在看就推送" },
  { key: "notify_health", title: "系统异常", hint: "AI 调用大量失败、做梦或画像出错时推送" },
  { key: "notify_learning", title: "学到新东西", hint: "学到新规矩，或夜间复盘总结出技能、坑" },
  { key: "notify_todo", title: "待办提醒", hint: "每天 9 点推送到期和逾期的待办" },
];

/** System health at a glance, push settings and the account. */
export default function MeScreen() {
  const t = useTheme();
  const { api, server, signOut } = useSession();
  const [me, setMe] = useState<Record<string, unknown> | null>(null);
  const [health, setHealth] = useState<Record<string, unknown> | null>(null);
  const [notify, setNotify] = useState<Record<string, unknown> | null>(null);
  const [barkUrl, setBarkUrl] = useState("");
  const [busy, setBusy] = useState<string | null>(null);
  const [message, setMessage] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);

  const load = useCallback(async () => {
    try {
      const [m, h, n] = await Promise.all([api.me(), api.health().catch(() => null), api.notifySettings().catch(() => null)]);
      setMe(m);
      setHealth(h);
      setNotify(n);
      setError(null);
    } catch (e) {
      setError(describeError(e));
    }
  }, [api]);

  useEffect(() => {
    void load();
  }, [load]);

  const saveNotify = async (fields: Record<string, unknown>, done?: string) => {
    setBusy(Object.keys(fields)[0] ?? "save");
    setMessage(null);
    try {
      setNotify(await api.updateNotifySettings(fields));
      if (done) setMessage(done);
    } catch (e) {
      setError(describeError(e));
    } finally {
      setBusy(null);
    }
  };

  const level = str(health?.level) || "ok";
  const issues = list(health?.issues);
  const ai = obj(health?.ai);
  const calls = obj(ai.calls);
  const total = num(calls.total);
  const success = total ? Math.floor(((num(calls.ok) + num(calls.fallback)) * 100) / total) : null;
  const learning = obj(health?.learning);
  const repeatPct = num(learning.total) ? Math.round((num(learning.repeat) * 100) / num(learning.total)) : null;
  const devices = obj(health?.devices);
  const levelColor = level === "error" ? t.danger : level === "warn" ? t.warn : t.success;

  return (
    <Screen title="我的" onRefresh={load}>
      {error && <Note>{error}</Note>}

      <Card>
        <Title trailing={health ? shortTime(health.generated_at) : undefined}>系统健康</Title>
        {!health && <Loading />}
        {health && (
          <>
            <View style={{ flexDirection: "row", alignItems: "center", gap: 10 }}>
              <View style={{ width: 10, height: 10, borderRadius: 5, backgroundColor: levelColor }} />
              <Text style={{ fontSize: 16, fontWeight: "600", color: t.fg1 }}>
                {level === "error" ? "有问题需要处理" : level === "warn" ? `有 ${issues.length} 处需要留意` : "一切正常"}
              </Text>
            </View>
            <Muted style={{ marginTop: 4, marginLeft: 20 }}>
              {num(devices.total)} 台设备 · {num(devices.online)} 台在线
            </Muted>
            {issues.map((issue, i) => (
              <Text key={i} style={{ fontSize: 13.5, color: issue.level === "error" ? t.danger : t.warn, marginTop: 8, lineHeight: 19 }}>
                · {str(issue.text)}
              </Text>
            ))}
            <Divider />
            <View style={{ flexDirection: "row", gap: 10 }}>
              <Metric label="24h AI 调用" value={String(total)} />
              <Metric label="成功率" value={success == null ? "—" : `${success}%`} color={success != null && success < 95 ? t.warn : undefined} />
              <Metric label="30 天纠正" value={String(num(learning.total))} />
              <Metric label="重复率" value={repeatPct == null ? "—" : `${repeatPct}%`} />
            </View>
          </>
        )}
      </Card>

      <Card>
        <Title>手机推送（Bark）</Title>
        <Muted>在 iPhone 上安装 Bark，复制首页的推送地址（https://api.day.app/…）粘贴到下面。</Muted>
        {!notify && <Loading />}
        {notify && (
          <>
            <Text style={{ fontSize: 13, color: notify.bark_configured ? t.success : t.fg3, marginTop: 10 }}>
              {notify.bark_configured ? `当前：${str(notify.bark_masked)}` : "当前：未设置"}
            </Text>
            <TextInput
              value={barkUrl}
              onChangeText={setBarkUrl}
              placeholder={notify.bark_configured ? "粘贴新地址可替换" : "https://api.day.app/…"}
              placeholderTextColor={t.fg4}
              autoCapitalize="none"
              keyboardType="url"
              style={{ fontSize: 14, color: t.fg1, backgroundColor: t.surfaceMute, borderRadius: radius.control, paddingHorizontal: 10, paddingVertical: 9, marginTop: 8 }}
            />
            <View style={{ flexDirection: "row", gap: 8, marginTop: 10, flexWrap: "wrap" }}>
              <Button small disabled={!barkUrl.trim()} busy={busy === "bark_url"} onPress={() => saveNotify({ bark_url: barkUrl.trim() }, "已保存，可以发条测试通知确认一下").then(() => setBarkUrl(""))}>
                保存
              </Button>
              <Button
                small
                variant="soft"
                disabled={!notify.bark_configured}
                busy={busy === "test"}
                onPress={async () => {
                  setBusy("test");
                  try {
                    await api.testNotification();
                    setMessage("已发送，看看手机有没有收到");
                  } catch (e) {
                    setError(describeError(e));
                  } finally {
                    setBusy(null);
                  }
                }}
              >
                发送测试通知
              </Button>
            </View>
            {message && <Muted style={{ marginTop: 8 }}>{message}</Muted>}
            <Divider />
            {SWITCHES.map((s) => (
              <View key={s.key} style={{ flexDirection: "row", alignItems: "center", gap: 10, paddingVertical: 6 }}>
                <View style={{ flex: 1 }}>
                  <Text style={{ fontSize: 14.5, color: t.fg1 }}>{s.title}</Text>
                  <Text style={{ fontSize: 12, color: t.fg3, marginTop: 1 }}>{s.hint}</Text>
                </View>
                <Switch
                  value={notify[s.key] !== false}
                  disabled={busy !== null}
                  onValueChange={(v) => saveNotify({ [s.key]: v })}
                  trackColor={{ true: t.accent, false: t.borderStrong }}
                />
              </View>
            ))}
          </>
        )}
      </Card>

      <Card>
        <Title>账号</Title>
        <Row left={str(me?.name) || str(me?.email) || "—"} right={str(me?.role)} sub={str(me?.email)} />
        <Row left="服务器" right={server.replace(/^https?:\/\//, "")} />
        <Row left="版本" right={Constants.expoConfig?.version ?? ""} />
        <View style={{ marginTop: 10 }}>
          <Button variant="danger" onPress={() => void signOut()}>
            退出登录
          </Button>
        </View>
      </Card>
    </Screen>
  );
}
