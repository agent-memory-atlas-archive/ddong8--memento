"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";
import { useEffect, useState } from "react";
import { useI18n } from "@/lib/i18n";
import { useAuth } from "@/lib/auth-context";
import { getApiBase, authFetch } from "@/lib/api-client";
import { Icon } from "@/components/aurora/Icon";
import { desktop } from "@/lib/desktop";
import pkg from "../../../package.json";

const WEB_VERSION = `v${(pkg as { version: string }).version}`;

type IconName = Parameters<typeof Icon>[0]["name"];

export default function Sidebar({ open, onClose }: { open: boolean; onClose: () => void }) {
  const pathname = usePathname();
  const { t } = useI18n();
  const { user } = useAuth();
  const [onlineCount, setOnlineCount] = useState<number>(0);
  const [totalDevices, setTotalDevices] = useState<number>(0);
  const [isMacDesktop, setIsMacDesktop] = useState(false);
  const [appVersion, setAppVersion] = useState(WEB_VERSION);

  useEffect(() => {
    const d = desktop();
    if (d) {
      const isMac =
        typeof navigator !== "undefined" &&
        (/Mac/i.test(navigator.userAgent) || /Mac/i.test((navigator as { platform?: string }).platform || ""));
      if (isMac) setIsMacDesktop(true);
    }
  }, []);

  useEffect(() => {
    const token = typeof window !== "undefined" ? localStorage.getItem("dr_token") : null;
    if (!token) return;

    const fetchDevices = () => {
      authFetch(`${getApiBase()}/api/devices`)
        .then((r) => r.json())
        .then((devs) => {
          if (!Array.isArray(devs)) return;
          setTotalDevices(devs.length);
          const now = Date.now();
          const online = devs.filter(
            (d) =>
              d.online ??
              (!!d.last_heartbeat && now - new Date(d.last_heartbeat).getTime() < 180000)
          ).length;
          setOnlineCount(online);
        })
        .catch(() => {});
    };

    fetchDevices();
    const timer = setInterval(fetchDevices, 30_000);
    return () => clearInterval(timer);
  }, []);

  useEffect(() => {
    authFetch(`${getApiBase()}/api/system/update/check`)
      .then((r) => r.json())
      .then((d) => {
        if (d?.latest_version) {
          const v = d.latest_version.startsWith("v") ? d.latest_version : `v${d.latest_version}`;
          setAppVersion(v);
        }
      })
      .catch(() => {});
  }, []);

  const handleNavClick = () => {
    if (typeof window !== "undefined" && window.innerWidth < 1024) onClose();
  };

  const isAskActive = pathname === "/ask" || (pathname.startsWith("/ask/") && !pathname.startsWith("/ask/tools"));
  const isOverviewActive = pathname === "/app";
  const isPersonaActive = pathname.startsWith("/memory/persona");
  const isMemoryActive = (pathname === "/memory" || pathname.startsWith("/memory/")) && !isPersonaActive;
  const isSkillsActive = pathname === "/skills" || pathname.startsWith("/skills/");
  const isDailyActive = pathname === "/daily" || pathname.startsWith("/daily/");
  const isProjectsActive = pathname === "/projects" || pathname.startsWith("/projects/");
  const isInboxActive = pathname === "/inbox" || pathname.startsWith("/inbox/");
  const isProfileActive = pathname === "/profile" || pathname.startsWith("/profile");

  return (
    <>
      {open && <div className="fixed inset-0 bg-black/50 z-30 lg:hidden" onClick={onClose} />}

      <aside
        className={[
          "fixed left-0 top-0 z-40 w-60 flex flex-col h-screen select-none",
          "transition-transform duration-200 ease-in-out",
          open ? "translate-x-0" : "-translate-x-full",
          "lg:!translate-x-0",
        ].join(" ")}
        style={{
          background: "var(--aurora-sidebar)",
          backdropFilter: "blur(24px) saturate(180%)",
          WebkitBackdropFilter: "blur(24px) saturate(180%)",
          borderRight: "1px solid var(--aurora-border)",
          color: "var(--aurora-fg2)",
        }}
      >
        {/* Brand */}
        <div
          className={`px-4 pb-3 flex items-center gap-3 ${isMacDesktop ? "pt-12 app-region-drag" : "pt-5"}`}
        >
          <Link
            href="/ask"
            onClick={handleNavClick}
            className="flex items-center gap-3 flex-1 min-w-0 app-region-no-drag"
          >
            <div
              style={{
                width: 34,
                height: 34,
                borderRadius: 11,
                background: "var(--aurora-brand-grad)",
                display: "flex",
                alignItems: "center",
                justifyContent: "center",
                boxShadow: "0 4px 14px -4px rgba(124,58,237,0.5)",
                flexShrink: 0,
              }}
            >
              <Icon name="sparkles" size={17} style={{ color: "#fff" }} strokeWidth={2} />
            </div>
            <div className="min-w-0">
              <div
                style={{
                  fontSize: 14,
                  fontWeight: 600,
                  color: "var(--aurora-fg1)",
                  letterSpacing: "-0.02em",
                  whiteSpace: "nowrap",
                  overflow: "hidden",
                  textOverflow: "ellipsis",
                }}
              >
                {t.app.title}
              </div>
              <div style={{ fontSize: 11, color: "var(--aurora-fg4)", marginTop: 1 }}>{t.app.subtitle}</div>
            </div>
          </Link>
          <button
            onClick={onClose}
            aria-label="Close"
            className="lg:hidden app-region-no-drag"
            style={{ color: "var(--aurora-fg3)", padding: 4 }}
          >
            <Icon name="close" size={18} />
          </button>
        </div>

        <div style={{ height: 1, background: "var(--aurora-border)", margin: "0 16px" }} />

        {/* Navigation */}
        <nav className="flex-1 overflow-y-auto py-2">
          {/* Section 1: 控制中枢 */}
          <SectionHeader label={t.nav.sectionExecutive || "控制中枢"} />
          <NavRow
            href="/ask"
            label={t.nav.ask || "远程控制"}
            icon="sparkles"
            active={isAskActive}
            badge="CORE"
            onClick={handleNavClick}
          />
          <NavRow
            href="/app"
            label={t.nav.dashboard || "运行看板"}
            icon="home"
            active={isOverviewActive}
            onClick={handleNavClick}
          />

          {/* Section 2: 认知大脑 (自进化) */}
          <SectionHeader label={t.nav.sectionBrain || "认知大脑"} style={{ marginTop: 14 }} />
          <NavRow
            href="/memory"
            label={t.nav.memory || "长期记忆"}
            icon="brain"
            active={isMemoryActive}
            onClick={handleNavClick}
          />
          <NavRow
            href="/memory/persona"
            label={t.nav.persona || "个人画像"}
            icon="user"
            active={isPersonaActive}
            onClick={handleNavClick}
          />
          <NavRow
            href="/skills"
            label={t.nav.skills || "技能进化"}
            icon="zap"
            active={isSkillsActive}
            onClick={handleNavClick}
          />

          {/* Section 3: 工作沉淀 */}
          <SectionHeader label={t.nav.sectionWorkspace || "工作沉淀"} style={{ marginTop: 14 }} />
          <NavRow
            href="/daily"
            label={t.nav.daily || "记忆日报"}
            icon="calendar"
            active={isDailyActive}
            onClick={handleNavClick}
          />
          <NavRow
            href="/projects"
            label={t.nav.projects || "项目工程"}
            icon="folder"
            active={isProjectsActive}
            onClick={handleNavClick}
          />
          <NavRow
            href="/inbox"
            label={t.nav.inbox || "待办清单"}
            icon="inbox"
            active={isInboxActive}
            onClick={handleNavClick}
          />
        </nav>

        {/* Bottom Section: Device status indicator + Settings + Version */}
        <div className="p-3" style={{ borderTop: "1px solid var(--aurora-border)" }}>
          {/* Online devices indicator */}
          <Link
            href="/profile?tab=devices"
            onClick={handleNavClick}
            className="flex items-center justify-between px-3 py-2 mb-2 rounded-xl text-xs transition-all hover:opacity-90"
            style={{
              background: onlineCount > 0 ? "rgba(16,185,129,0.08)" : "var(--aurora-chip)",
              border: onlineCount > 0 ? "1px solid rgba(16,185,129,0.25)" : "1px solid var(--aurora-border)",
              color: "var(--aurora-fg2)",
              textDecoration: "none",
            }}
            title="点击管理终端设备"
          >
            <div className="flex items-center gap-2 min-w-0">
              <span
                style={{
                  width: 6,
                  height: 6,
                  borderRadius: 9999,
                  background: onlineCount > 0 ? "#10B981" : "var(--aurora-fg4)",
                  boxShadow: onlineCount > 0 ? "0 0 6px #10B981" : "none",
                  flexShrink: 0,
                }}
              />
              <span style={{ fontSize: 11.5, fontWeight: 500, overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap" }}>
                {onlineCount > 0
                  ? (t.nav.onlineCount || "{n} 台设备在线").replace("{n}", String(onlineCount))
                  : (t.nav.noOnline || "无在线设备")}
              </span>
            </div>
            <span style={{ color: "var(--aurora-fg4)", fontSize: 10.5 }}>
              {totalDevices > 0 ? `${totalDevices}台` : "管理"} &rarr;
            </span>
          </Link>

          {/* Settings entry */}
          <NavRow
            href="/profile"
            label={t.nav.settings || "个人设置"}
            icon="settings"
            active={isProfileActive}
            onClick={handleNavClick}
          />

          {/* Version badge */}
          <div
            style={{
              fontSize: 10.5,
              color: "var(--aurora-fg4)",
              textAlign: "center",
              paddingTop: 8,
              fontFamily: "var(--font-mono, ui-monospace, monospace)",
              letterSpacing: "0.03em",
            }}
          >
            {appVersion}
          </div>
        </div>
      </aside>
    </>
  );
}

function SectionHeader({ label, style }: { label: string; style?: React.CSSProperties }) {
  return (
    <div
      style={{
        padding: "6px 14px 4px 16px",
        fontSize: 11,
        fontWeight: 600,
        color: "var(--aurora-fg4)",
        letterSpacing: "0.04em",
        textTransform: "uppercase",
        display: "flex",
        alignItems: "center",
        ...style,
      }}
    >
      {label}
    </div>
  );
}

function NavRow({
  href,
  label,
  icon,
  active,
  badge,
  onClick,
}: {
  href: string;
  label: string;
  icon: IconName;
  active: boolean;
  badge?: string;
  onClick?: () => void;
}) {
  const [hover, setHover] = useState(false);
  const color = active
    ? "var(--aurora-accent)"
    : hover
    ? "var(--aurora-fg1)"
    : "var(--aurora-fg2)";

  const bg = active
    ? "var(--aurora-accent-soft)"
    : hover
    ? "var(--aurora-chip)"
    : "transparent";

  return (
    <Link
      href={href}
      onClick={onClick}
      onMouseEnter={() => setHover(true)}
      onMouseLeave={() => setHover(false)}
      style={{
        display: "flex",
        alignItems: "center",
        gap: 11,
        padding: "8px 14px",
        margin: "1.5px 8px",
        borderRadius: 12,
        color,
        background: bg,
        fontSize: 13,
        fontWeight: active ? 600 : 450,
        letterSpacing: "-0.01em",
        textDecoration: "none",
        transition: "all .15s",
      }}
    >
      <Icon
        name={icon}
        size={16}
        color={active ? "var(--aurora-accent)" : undefined}
      />
      <span style={{ flex: 1, overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap" }}>
        {label}
      </span>
      {badge && (
        <span
          style={{
            fontSize: 9,
            fontWeight: 700,
            padding: "1px 5px",
            borderRadius: 5,
            background: active ? "var(--aurora-accent)" : "rgba(124,58,237,0.14)",
            color: active ? "#fff" : "var(--aurora-accent)",
            letterSpacing: "0.04em",
          }}
        >
          {badge}
        </span>
      )}
      {active && !badge && (
        <span
          style={{
            width: 5,
            height: 5,
            borderRadius: 9999,
            background: "var(--aurora-accent)",
            flexShrink: 0,
          }}
        />
      )}
    </Link>
  );
}
