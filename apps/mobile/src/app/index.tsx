import Constants from "expo-constants";
import { Redirect } from "expo-router";
import { StatusBar } from "expo-status-bar";
import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import { ActivityIndicator, BackHandler, Linking, Platform, StyleSheet, Text, View } from "react-native";
import * as Notifications from "expo-notifications";
import { useSafeAreaInsets } from "react-native-safe-area-context";
import { WebView, type WebViewMessageEvent, type WebViewNavigation, type WebViewProps } from "react-native-webview";

import { Button } from "../components/ui";
import { triggerLocalNotification } from "../lib/notifications";
import { useSession } from "../lib/session";
import { useTheme } from "../lib/theme";

// The web app is the interface, as in the desktop app. The page reports its
// background so the status bar and home-indicator strips match its skin and theme.
const REPORT_THEME = `(() => {
  const post = () => {
    const root = document.documentElement;
    const bg = getComputedStyle(document.body || root).backgroundColor;
    window.ReactNativeWebView.postMessage(JSON.stringify({ type: "theme", bg, dark: root.getAttribute("data-theme") === "dark" }));
  };
  post();
  new MutationObserver(post).observe(document.documentElement, { attributes: true, attributeFilter: ["data-theme", "data-skin"] });
})();
true;`;

type ShouldStartLoadRequest = Parameters<NonNullable<WebViewProps["onShouldStartLoadWithRequest"]>>[0];

const USER_AGENT_SUFFIX = `MementoMobile/${Constants.expoConfig?.version ?? "0"}`;

function sameOrigin(url: string, origin: string): boolean {
  return url.startsWith(origin) && /^(?:[/?#]|$)/.test(url.slice(origin.length));
}

function isLoginPage(url: string, origin: string): boolean {
  return sameOrigin(url, origin) && /^\/auth\/login(?:[/?#]|$)/.test(url.slice(origin.length));
}

export default function WebShell() {
  const t = useTheme();
  const insets = useSafeAreaInsets();
  const { ready, server, token, signOut } = useSession();
  const web = useRef<WebView>(null);
  const canGoBack = useRef(false);
  const [page, setPage] = useState<{ bg: string; dark: boolean } | null>(null);

  const origin = useMemo(() => server.match(/^https?:\/\/[^/]+/i)?.[0] ?? server, [server]);
  // Sign the page in with the app's token, then land directly on the Command Center (/ask).
  const start = useMemo(() => (token ? `${origin}/auth/handoff#token=${encodeURIComponent(token)}&next=%2Fask` : null), [origin, token]);

  useEffect(() => {
    if (Platform.OS !== "android") return;
    const sub = BackHandler.addEventListener("hardwareBackPress", () => {
      if (!canGoBack.current) return false;
      web.current?.goBack();
      return true;
    });
    return () => sub.remove();
  }, []);

  // Open destination URL when a native push notification is tapped
  useEffect(() => {
    void Notifications.getLastNotificationResponseAsync().then((response) => {
      const target = response?.notification.request.content.data?.url as string | undefined;
      if (target && web.current) {
        const fullUrl = target.startsWith("http") ? target : `${origin}${target.startsWith("/") ? "" : "/"}${target}`;
        web.current.injectJavaScript(`window.location.assign(${JSON.stringify(fullUrl)}); true;`);
      }
    });

    const sub = Notifications.addNotificationResponseReceivedListener((response) => {
      const target = response.notification.request.content.data?.url as string | undefined;
      if (target && web.current) {
        const fullUrl = target.startsWith("http") ? target : `${origin}${target.startsWith("/") ? "" : "/"}${target}`;
        web.current.injectJavaScript(`window.location.assign(${JSON.stringify(fullUrl)}); true;`);
      }
    });

    return () => sub.remove();
  }, [origin]);

  const onNavigation = useCallback(
    (nav: WebViewNavigation) => {
      canGoBack.current = nav.canGoBack;
      // The page signed out or its token expired: sign in again natively.
      if (isLoginPage(nav.url, origin)) void signOut();
    },
    [origin, signOut],
  );

  const onShouldStart = useCallback(
    (req: ShouldStartLoadRequest) => {
      if (req.isTopFrame === false) return true;
      const { url } = req;
      if (sameOrigin(url, origin)) {
        if (isLoginPage(url, origin)) {
          void signOut();
          return false;
        }
        return true;
      }
      if (/^(about|data|blob):/i.test(url)) return true;
      void Linking.openURL(url).catch(() => undefined);
      return false;
    },
    [origin, signOut],
  );

  const onOpenWindow = useCallback(
    (url: string) => {
      if (sameOrigin(url, origin)) web.current?.injectJavaScript(`window.location.assign(${JSON.stringify(url)}); true;`);
      else void Linking.openURL(url).catch(() => undefined);
    },
    [origin],
  );

  // Real-time server notification synchronization & instant native popups
  useEffect(() => {
    if (!ready || !token) return;
    let cancelled = false;
    let timer: ReturnType<typeof setInterval> | null = null;
    let lastSeen = new Date().toISOString();

    const fetchFeed = async () => {
      try {
        const base = origin.replace(/\/+$/, "");
        const res = await fetch(`${base}/api/notify/feed?since=${encodeURIComponent(lastSeen)}`, {
          headers: { Authorization: `Bearer ${token}` },
        });
        if (res.ok) {
          const items = (await res.json()) as Array<{
            id: string;
            title: string;
            body: string;
            url?: string;
            created_at: string;
          }>;
          if (Array.isArray(items) && items.length > 0) {
            for (const item of items) {
              await triggerLocalNotification(item.title, item.body, { url: item.url });
              if (item.created_at > lastSeen) {
                lastSeen = item.created_at;
              }
            }
          }
        }
      } catch {
        // silent on network error
      }
    };

    void fetchFeed();
    timer = setInterval(() => {
      if (!cancelled) void fetchFeed();
    }, 4000);

    return () => {
      cancelled = true;
      if (timer) clearInterval(timer);
    };
  }, [ready, token, origin]);

  const onMessage = useCallback((e: WebViewMessageEvent) => {
    try {
      const msg = JSON.parse(e.nativeEvent.data) as {
        type?: string;
        bg?: string;
        dark?: boolean;
        title?: string;
        body?: string;
        data?: Record<string, unknown>;
      };
      if (msg.type === "theme" && msg.bg && !/rgba\(0, 0, 0, 0\)|transparent/.test(msg.bg)) {
        setPage({ bg: msg.bg, dark: !!msg.dark });
      } else if (msg.type === "notify" && msg.title) {
        void triggerLocalNotification(msg.title, msg.body || "", msg.data);
      }
    } catch {
      // not ours
    }
  }, []);

  if (!ready) return <View style={{ flex: 1, backgroundColor: t.bg }} />;
  if (!token || !start) return <Redirect href="/login" />;

  const bg = page?.bg ?? t.bg;
  const dark = page ? page.dark : t.scheme === "dark";

  return (
    <View style={{ flex: 1, backgroundColor: bg, paddingTop: insets.top, paddingBottom: insets.bottom }}>
      <StatusBar style={dark ? "light" : "dark"} />
      <WebView
        ref={web}
        source={{ uri: start }}
        style={{ flex: 1, backgroundColor: bg }}
        applicationNameForUserAgent={USER_AGENT_SUFFIX}
        injectedJavaScript={REPORT_THEME}
        onMessage={onMessage}
        onNavigationStateChange={onNavigation}
        onShouldStartLoadWithRequest={onShouldStart}
        onOpenWindow={(e) => onOpenWindow(e.nativeEvent.targetUrl)}
        onContentProcessDidTerminate={() => web.current?.reload()}
        onRenderProcessGone={() => web.current?.reload()}
        allowsBackForwardNavigationGestures
        decelerationRate="normal"
        textZoom={100}
        webviewDebuggingEnabled={__DEV__}
        startInLoadingState
        renderLoading={() => (
          <View style={[StyleSheet.absoluteFill, { alignItems: "center", justifyContent: "center", backgroundColor: bg }]}>
            <ActivityIndicator color={t.accent} />
          </View>
        )}
        renderError={() => (
          <View style={[StyleSheet.absoluteFill, { alignItems: "center", justifyContent: "center", gap: 14, padding: 24, backgroundColor: t.bg }]}>
            <Text style={{ fontSize: 16, fontWeight: "600", color: t.fg1 }}>连不上 Memento</Text>
            <Text style={{ fontSize: 13, color: t.fg3, textAlign: "center" }}>检查网络后重试（{origin}）</Text>
            <Button onPress={() => web.current?.reload()}>重试</Button>
          </View>
        )}
      />
    </View>
  );
}
