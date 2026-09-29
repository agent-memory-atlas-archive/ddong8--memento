import { Redirect } from "expo-router";
import { useState } from "react";
import { KeyboardAvoidingView, Linking, Platform, Text, TextInput, View } from "react-native";
import { SafeAreaView } from "react-native-safe-area-context";
import Svg, { Circle, Defs, LinearGradient, RadialGradient, Rect, Stop } from "react-native-svg";

import { Button, Note } from "../components/ui";
import { describeError } from "../lib/api";
import { DEFAULT_SERVER, useSession } from "../lib/session";
import { radius, useTheme } from "../lib/theme";

function Mark() {
  return (
    <Svg width={64} height={64} viewBox="0 0 64 64">
      <Defs>
        <LinearGradient id="g" x1="0" y1="0" x2="1" y2="1">
          <Stop offset="0" stopColor="#7C3AED" />
          <Stop offset="0.55" stopColor="#EC4899" />
          <Stop offset="1" stopColor="#06B6D4" />
        </LinearGradient>
        <RadialGradient id="c" cx="0.5" cy="0.5" r="0.5">
          <Stop offset="0" stopColor="#ffffff" stopOpacity={0.95} />
          <Stop offset="0.6" stopColor="#ffffff" stopOpacity={0.4} />
          <Stop offset="1" stopColor="#ffffff" stopOpacity={0} />
        </RadialGradient>
      </Defs>
      <Rect x={2} y={2} width={60} height={60} rx={16} fill="url(#g)" />
      <Circle cx={32} cy={32} r={14} fill="url(#c)" />
      <Circle cx={32} cy={32} r={5} fill="#ffffff" />
    </Svg>
  );
}

export default function LoginScreen() {
  const t = useTheme();
  const { token, signIn, server: savedServer } = useSession();
  const [server, setServer] = useState(savedServer || DEFAULT_SERVER);
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [showServer, setShowServer] = useState(false);

  if (token) return <Redirect href="/" />;

  const submit = async () => {
    setBusy(true);
    setError(null);
    try {
      await signIn(server, email, password);
    } catch (e) {
      setError(describeError(e));
    } finally {
      setBusy(false);
    }
  };

  const field = { fontSize: 15, color: t.fg1, backgroundColor: t.surface, borderRadius: radius.control, borderWidth: 1, borderColor: t.border, paddingHorizontal: 12, paddingVertical: 12 } as const;

  return (
    <SafeAreaView style={{ flex: 1, backgroundColor: t.bg }}>
      <KeyboardAvoidingView style={{ flex: 1, justifyContent: "center", padding: 24 }} behavior={Platform.OS === "ios" ? "padding" : undefined}>
        <View style={{ alignItems: "center", marginBottom: 28, gap: 10 }}>
          <Mark />
          <Text style={{ fontSize: 26, fontWeight: "700", color: t.fg1 }}>Memento</Text>
          <Text style={{ fontSize: 14, color: t.fg3 }}>你的 AI 外脑，随身带着</Text>
        </View>
        {error && <Note>{error}</Note>}
        <View style={{ gap: 10, width: "100%", maxWidth: 420, alignSelf: "center" }}>
          <TextInput value={email} onChangeText={setEmail} placeholder="邮箱" placeholderTextColor={t.fg4} autoCapitalize="none" keyboardType="email-address" autoComplete="email" style={field} />
          <TextInput value={password} onChangeText={setPassword} placeholder="密码" placeholderTextColor={t.fg4} secureTextEntry autoComplete="password" onSubmitEditing={submit} style={field} />
          {showServer && <TextInput value={server} onChangeText={setServer} placeholder={DEFAULT_SERVER} placeholderTextColor={t.fg4} autoCapitalize="none" keyboardType="url" style={field} />}
          <Button onPress={submit} busy={busy} disabled={!email.trim() || !password}>
            登录
          </Button>
          <View style={{ flexDirection: "row", justifyContent: "center", gap: 20, marginTop: 6 }}>
            <Text onPress={() => void Linking.openURL(`${(server.trim() || DEFAULT_SERVER).replace(/\/+$/, "")}/auth/register`)} style={{ fontSize: 13, color: t.accent }}>
              注册账号
            </Text>
            <Text onPress={() => setShowServer((v) => !v)} style={{ fontSize: 13, color: t.fg3 }}>
              {showServer ? "收起服务器地址" : "自建服务器？"}
            </Text>
          </View>
        </View>
      </KeyboardAvoidingView>
    </SafeAreaView>
  );
}
