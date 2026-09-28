import type { ReactNode } from "react";
import { ActivityIndicator, Pressable, Text, View, type StyleProp, type TextStyle, type ViewStyle } from "react-native";

import { radius, useTheme } from "../lib/theme";
import { Icon, type IconName } from "./Icon";

export function Card({ children, style, accent }: { children: ReactNode; style?: StyleProp<ViewStyle>; accent?: boolean }) {
  const t = useTheme();
  return (
    <View
      style={[
        {
          backgroundColor: t.surface,
          borderRadius: radius.card,
          borderWidth: 1,
          borderColor: accent ? t.accent : t.border,
          padding: 16,
          marginBottom: 12,
        },
        style,
      ]}
    >
      {children}
    </View>
  );
}

export function Title({ children, trailing }: { children: ReactNode; trailing?: ReactNode }) {
  const t = useTheme();
  return (
    <View style={{ flexDirection: "row", alignItems: "center", marginBottom: 10, gap: 8 }}>
      <Text style={{ flex: 1, fontSize: 15, fontWeight: "600", color: t.fg1 }}>{children}</Text>
      {typeof trailing === "string" ? <Text style={{ fontSize: 12, color: t.fg3 }}>{trailing}</Text> : trailing}
    </View>
  );
}

export function Muted({ children, style }: { children: ReactNode; style?: StyleProp<TextStyle> }) {
  const t = useTheme();
  return <Text style={[{ fontSize: 13, color: t.fg3, lineHeight: 19 }, style]}>{children}</Text>;
}

type Tone = "neutral" | "accent" | "success" | "warn" | "danger";

export function Chip({ children, tone = "neutral" }: { children: ReactNode; tone?: Tone }) {
  const t = useTheme();
  const colors: Record<Tone, [string, string]> = {
    neutral: [t.surfaceMute, t.fg2],
    accent: [t.accentSoft, t.accent],
    success: [t.successSoft, t.success],
    warn: [t.warnSoft, t.warn],
    danger: [t.dangerSoft, t.danger],
  };
  const [bg, fg] = colors[tone];
  return (
    <View style={{ backgroundColor: bg, borderRadius: radius.chip, paddingHorizontal: 8, paddingVertical: 3, alignSelf: "flex-start" }}>
      <Text style={{ fontSize: 12, fontWeight: "600", color: fg }}>{children}</Text>
    </View>
  );
}

export function Button({
  children,
  onPress,
  variant = "primary",
  icon,
  disabled,
  busy,
  small,
}: {
  children?: ReactNode;
  onPress?: () => void;
  variant?: "primary" | "ghost" | "soft" | "danger";
  icon?: IconName;
  disabled?: boolean;
  busy?: boolean;
  small?: boolean;
}) {
  const t = useTheme();
  const bg = variant === "primary" ? t.accent : variant === "soft" ? t.accentSoft : variant === "danger" ? t.dangerSoft : "transparent";
  const fg = variant === "primary" ? t.onAccent : variant === "danger" ? t.danger : variant === "ghost" ? t.fg2 : t.accent;
  return (
    <Pressable
      onPress={onPress}
      disabled={disabled || busy}
      style={({ pressed }) => ({
        flexDirection: "row",
        alignItems: "center",
        justifyContent: "center",
        gap: 6,
        backgroundColor: bg,
        borderRadius: radius.control,
        paddingHorizontal: small ? 10 : 14,
        paddingVertical: small ? 6 : 10,
        opacity: disabled ? 0.45 : pressed ? 0.75 : 1,
        borderWidth: variant === "ghost" ? 1 : 0,
        borderColor: t.border,
      })}
    >
      {busy ? <ActivityIndicator size="small" color={fg} /> : icon ? <Icon name={icon} size={small ? 14 : 16} color={fg} /> : null}
      {children != null && <Text style={{ color: fg, fontSize: small ? 13 : 14, fontWeight: "600" }}>{children}</Text>}
    </Pressable>
  );
}

export function Note({ children, tone = "danger" }: { children: ReactNode; tone?: "danger" | "warn" | "info" }) {
  const t = useTheme();
  const [bg, fg] = tone === "danger" ? [t.dangerSoft, t.danger] : tone === "warn" ? [t.warnSoft, t.warn] : [t.accentSoft, t.fg2];
  return (
    <View style={{ backgroundColor: bg, borderRadius: radius.control, padding: 12, marginBottom: 12 }}>
      <Text style={{ color: fg, fontSize: 13, lineHeight: 19 }}>{children}</Text>
    </View>
  );
}

export function Metric({ label, value, color }: { label: string; value: string; color?: string }) {
  const t = useTheme();
  return (
    <View style={{ flex: 1, minWidth: 70 }}>
      <Text style={{ fontSize: 20, fontWeight: "600", color: color ?? t.fg1, fontVariant: ["tabular-nums"] }} numberOfLines={1} adjustsFontSizeToFit>
        {value}
      </Text>
      <Text style={{ fontSize: 12, color: t.fg3, marginTop: 2 }}>{label}</Text>
    </View>
  );
}

export function Row({ left, right, sub, rightColor, onPress }: { left: string; right?: string; sub?: string | null; rightColor?: string; onPress?: () => void }) {
  const t = useTheme();
  const body = (
    <View style={{ flexDirection: "row", gap: 10, paddingVertical: 7, alignItems: "flex-start" }}>
      <View style={{ flex: 1 }}>
        <Text style={{ fontSize: 14, color: t.fg1 }}>{left}</Text>
        {!!sub && <Text style={{ fontSize: 12, color: t.fg3, marginTop: 2 }}>{sub}</Text>}
      </View>
      {!!right && <Text style={{ fontSize: 13, color: rightColor ?? t.fg2, maxWidth: "45%", textAlign: "right" }}>{right}</Text>}
    </View>
  );
  return onPress ? <Pressable onPress={onPress}>{body}</Pressable> : body;
}

export function Divider() {
  const t = useTheme();
  return <View style={{ height: 1, backgroundColor: t.border, marginVertical: 8 }} />;
}

export function Loading() {
  const t = useTheme();
  return (
    <View style={{ padding: 32, alignItems: "center" }}>
      <ActivityIndicator color={t.accent} />
    </View>
  );
}
