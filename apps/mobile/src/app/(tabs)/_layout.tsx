import { Redirect, Tabs } from "expo-router";

import { Icon, type IconName } from "../../components/Icon";
import { useSession } from "../../lib/session";
import { useTheme } from "../../lib/theme";

const TABS: { name: string; title: string; icon: IconName }[] = [
  { name: "index", title: "问答", icon: "sparkles" },
  { name: "memory", title: "记忆", icon: "brain" },
  { name: "devices", title: "设备", icon: "devices" },
  { name: "daily", title: "日报", icon: "calendar" },
  { name: "me", title: "我的", icon: "user" },
];

export default function TabsLayout() {
  const t = useTheme();
  const { ready, token } = useSession();
  if (ready && !token) return <Redirect href="/login" />;
  return (
    <Tabs
      screenOptions={{
        headerShown: false,
        tabBarActiveTintColor: t.accent,
        tabBarInactiveTintColor: t.fg3,
        tabBarStyle: { backgroundColor: t.surface, borderTopColor: t.border },
      }}
    >
      {TABS.map((tab) => (
        <Tabs.Screen key={tab.name} name={tab.name} options={{ title: tab.title, tabBarIcon: ({ color, size }) => <Icon name={tab.icon} size={size - 2} color={color} /> }} />
      ))}
    </Tabs>
  );
}
