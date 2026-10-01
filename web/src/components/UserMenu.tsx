"use client";

import { useEffect, useRef, useState } from "react";
import Link from "next/link";
import { useAuth } from "@/lib/auth-context";
import { useI18n } from "@/lib/i18n";
import { Icon } from "@/components/aurora/Icon";
import { desktop } from "@/lib/desktop";

type IconName = Parameters<typeof Icon>[0]["name"];

/** Avatar button + popup menu (profile / devices / health / admin / logout). Click outside to close. */
export function UserMenu() {
  const { user, logout } = useAuth();
  const { t } = useI18n();
  const [open, setOpen] = useState(false);
  const [isDesktop, setIsDesktop] = useState(false);
  const ref = useRef<HTMLDivElement>(null);

  useEffect(() => {
    if (desktop()) setIsDesktop(true);
  }, []);

  useEffect(() => {
    if (!open) return;
    const onDown = (e: MouseEvent) => {
      if (ref.current && !ref.current.contains(e.target as Node)) setOpen(false);
    };
    const onEsc = (e: KeyboardEvent) => {
      if (e.key === "Escape") setOpen(false);
    };
    document.addEventListener("mousedown", onDown);
    document.addEventListener("keydown", onEsc);
    return () => {
      document.removeEventListener("mousedown", onDown);
      document.removeEventListener("keydown", onEsc);
    };
  }, [open]);

  if (!user) return null;

  const initial = (user.name || user.email)[0]?.toUpperCase() || "?";
  const displayName = user.name || user.email;
  const isAdmin = user.role === "admin" || user.role === "owner";

  return (
    <div ref={ref} style={{ position: "relative" }}>
      <button
        type="button"
        onClick={() => setOpen((v) => !v)}
        aria-label={t.profile.title}
        aria-expanded={open}
        aria-haspopup="menu"
        style={{
          width: 32,
          height: 32,
          borderRadius: 9999,
          overflow: "hidden",
          background: "var(--aurora-primary-grad)",
          color: "#fff",
          display: "inline-flex",
          alignItems: "center",
          justifyContent: "center",
          fontSize: 13,
          fontWeight: 600,
          cursor: "pointer",
          border: "1px solid var(--aurora-border)",
          padding: 0,
          boxShadow: open
            ? "0 0 0 2px color-mix(in srgb, var(--aurora-accent) 40%, transparent)"
            : "none",
          transition: "box-shadow .15s",
        }}
      >
        {user.avatar_url ? (
          // eslint-disable-next-line @next/next/no-img-element
          <img
            src={user.avatar_url}
            alt={displayName}
            style={{ width: "100%", height: "100%", objectFit: "cover" }}
          />
        ) : (
          initial
        )}
      </button>

      {open && (
        <div
          role="menu"
          style={{
            position: "absolute",
            top: "calc(100% + 8px)",
            right: 0,
            minWidth: 230,
            background: "var(--aurora-surface)",
            border: "1px solid var(--aurora-border)",
            borderRadius: 14,
            boxShadow: "0 16px 40px -12px rgba(0,0,0,0.25)",
            backdropFilter: "blur(24px) saturate(180%)",
            WebkitBackdropFilter: "blur(24px) saturate(180%)",
            padding: 6,
            zIndex: 50,
          }}
        >
          {/* Header: avatar + name + email + role chip */}
          <div
            style={{
              padding: "10px 12px 12px",
              borderBottom: "1px solid var(--aurora-border)",
              marginBottom: 4,
              display: "flex",
              alignItems: "center",
              gap: 10,
            }}
          >
            <div
              style={{
                width: 36,
                height: 36,
                borderRadius: 9999,
                overflow: "hidden",
                background: "var(--aurora-primary-grad)",
                color: "#fff",
                display: "inline-flex",
                alignItems: "center",
                justifyContent: "center",
                fontSize: 14,
                fontWeight: 600,
                flexShrink: 0,
                border: "1px solid var(--aurora-border)",
              }}
            >
              {user.avatar_url ? (
                // eslint-disable-next-line @next/next/no-img-element
                <img
                  src={user.avatar_url}
                  alt={displayName}
                  style={{ width: "100%", height: "100%", objectFit: "cover" }}
                />
              ) : (
                initial
              )}
            </div>
            <div style={{ minWidth: 0, flex: 1 }}>
              <div
                style={{
                  fontSize: 13,
                  fontWeight: 600,
                  color: "var(--aurora-fg1)",
                  letterSpacing: "-0.01em",
                  overflow: "hidden",
                  textOverflow: "ellipsis",
                  whiteSpace: "nowrap",
                }}
                title={displayName}
              >
                {displayName}
              </div>
              {user.name && (
                <div
                  style={{
                    fontSize: 11,
                    color: "var(--aurora-fg4)",
                    marginTop: 1,
                    overflow: "hidden",
                    textOverflow: "ellipsis",
                    whiteSpace: "nowrap",
                  }}
                  title={user.email}
                >
                  {user.email}
                </div>
              )}
              <div
                style={{
                  display: "inline-block",
                  marginTop: 4,
                  fontSize: 10,
                  padding: "1px 6px",
                  borderRadius: 9999,
                  background: "var(--aurora-chip)",
                  color: "var(--aurora-fg3)",
                  fontWeight: 500,
                }}
              >
                {user.role}
              </div>
            </div>
          </div>

          {/* Quick shortcuts */}
          <MenuLink href="/profile" icon="settings" onClick={() => setOpen(false)}>
            {t.profile.title || "个人设置"}
          </MenuLink>
          <MenuLink href="/profile?tab=devices" icon="devices" onClick={() => setOpen(false)}>
            {t.profile.tabs?.devices || "我的设备"}
          </MenuLink>
          <MenuLink href="/profile?tab=health" icon="activity" onClick={() => setOpen(false)}>
            {t.profile.tabs?.health || "系统健康"}
          </MenuLink>
          {isDesktop && (
            <MenuLink href="/profile?tab=collector" icon="terminal" onClick={() => setOpen(false)}>
              {t.profile.tabs?.collector || "本机采集"}
            </MenuLink>
          )}

          {isAdmin && (
            <>
              <div style={{ height: 1, background: "var(--aurora-border)", margin: "4px 8px" }} />
              <MenuLink href="/admin" icon="lock" onClick={() => setOpen(false)}>
                {t.nav.admin || "管理后台"}
              </MenuLink>
            </>
          )}

          <div style={{ height: 1, background: "var(--aurora-border)", margin: "4px 8px" }} />

          <MenuButton icon="log_out" onClick={() => { setOpen(false); logout(); }} tone="danger">
            {t.profile.logout}
          </MenuButton>
        </div>
      )}
    </div>
  );
}

const menuItemStyle: React.CSSProperties = {
  display: "flex",
  alignItems: "center",
  gap: 10,
  width: "100%",
  padding: "8px 12px",
  borderRadius: 8,
  fontSize: 13,
  textDecoration: "none",
  background: "transparent",
  border: 0,
  cursor: "pointer",
  textAlign: "left",
  transition: "background .1s",
};

function MenuLink({
  href, icon, children, onClick,
}: {
  href: string; icon: IconName; children: React.ReactNode; onClick?: () => void;
}) {
  return (
    <Link
      href={href}
      onClick={onClick}
      style={{ ...menuItemStyle, color: "var(--aurora-fg1)" }}
      onMouseEnter={(e) => (e.currentTarget.style.background = "var(--aurora-chip)")}
      onMouseLeave={(e) => (e.currentTarget.style.background = "transparent")}
    >
      <Icon name={icon} size={15} />
      {children}
    </Link>
  );
}

function MenuButton({
  icon, children, onClick, tone = "default",
}: {
  icon: IconName;
  children: React.ReactNode;
  onClick: () => void;
  tone?: "default" | "danger";
}) {
  const color = tone === "danger" ? "#DC2626" : "var(--aurora-fg1)";
  return (
    <button
      type="button"
      onClick={onClick}
      style={{ ...menuItemStyle, color }}
      onMouseEnter={(e) => (e.currentTarget.style.background = "var(--aurora-chip)")}
      onMouseLeave={(e) => (e.currentTarget.style.background = "transparent")}
    >
      <Icon name={icon} size={15} />
      {children}
    </button>
  );
}
