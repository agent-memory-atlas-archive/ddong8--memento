"use client";

import { Suspense, useEffect, useRef, useState } from "react";
import { useSearchParams, useRouter } from "next/navigation";
import Link from "next/link";
import { useAuth } from "@/lib/auth-context";
import { useI18n } from "@/lib/i18n";
import { api } from "@/lib/api-client";
import { desktop } from "@/lib/desktop";
import { Btn, Chip, Glass, TopBar, SectionLabel, GhostInput } from "@/components/aurora/primitives";
import { Icon } from "@/components/aurora/Icon";
import NotifySettings from "@/components/notify/NotifySettings";
import { DevicesView } from "@/components/devices/DevicesView";
import { CollectorView } from "@/components/collector/CollectorView";
import { StatusView } from "@/components/status/StatusView";

type TabKey = "account" | "devices" | "collector" | "health" | "admin";

type ImportSummary = {
  machine_id: string;
  counts: Record<string, number>;
  warnings: string[];
};

export default function ProfilePage() {
  return (
    <Suspense
      fallback={
        <div style={{ textAlign: "center", color: "var(--aurora-fg4)", marginTop: 80 }}>
          加载设置...
        </div>
      }
    >
      <ProfileContent />
    </Suspense>
  );
}

function ProfileContent() {
  const { user, token, logout, setUser } = useAuth();
  const { t } = useI18n();
  const searchParams = useSearchParams();
  const router = useRouter();

  const [activeTab, setActiveTab] = useState<TabKey>("account");
  const [isDesktopEnv, setIsDesktopEnv] = useState(false);

  useEffect(() => {
    const d = desktop();
    if (d) setIsDesktopEnv(true);
  }, []);

  useEffect(() => {
    const paramTab = searchParams.get("tab") as TabKey | null;
    if (paramTab && ["account", "devices", "collector", "health", "admin"].includes(paramTab)) {
      setActiveTab(paramTab);
    }
  }, [searchParams]);

  const switchTab = (tab: TabKey) => {
    setActiveTab(tab);
    router.replace(`/profile?tab=${tab}`, { scroll: false });
  };

  const isAdmin = user?.role === "admin" || user?.role === "owner";

  if (!user) {
    return (
      <div style={{ textAlign: "center", color: "var(--aurora-fg4)", marginTop: 80 }}>
        {t.loading}
      </div>
    );
  }

  const TABS: { id: TabKey; label: string; icon: Parameters<typeof Icon>[0]["name"]; adminOnly?: boolean }[] = [
    { id: "account", label: t.profile.tabs?.account || "账号安全", icon: "user" },
    { id: "devices", label: t.profile.tabs?.devices || "我的设备", icon: "devices" },
    { id: "collector", label: t.profile.tabs?.collector || "采集配置", icon: "terminal" },
    { id: "health", label: t.profile.tabs?.health || "系统健康", icon: "activity" },
    ...(isAdmin ? [{ id: "admin" as TabKey, label: t.profile.tabs?.admin || "管理控制台", icon: "lock" as const }] : []),
  ];

  return (
    <div className="max-w-4xl mx-auto pb-16">
      <TopBar title={t.profile.title || "个人设置"} subtitle={t.profile.subtitle || "账号偏好、终端设备与系统运维"} />

      {/* Tabs navigation */}
      <div
        className="flex items-center gap-1.5 p-1 mb-6 rounded-2xl overflow-x-auto no-scrollbar"
        style={{
          background: "var(--aurora-card)",
          border: "1px solid var(--aurora-border)",
          boxShadow: "0 2px 10px rgba(0,0,0,0.03)",
        }}
      >
        {TABS.map((tab) => {
          const active = activeTab === tab.id;
          return (
            <button
              key={tab.id}
              onClick={() => switchTab(tab.id)}
              className="flex items-center gap-2 px-3.5 py-2 rounded-xl text-xs sm:text-sm font-medium transition-all whitespace-nowrap cursor-pointer"
              style={{
                background: active ? "var(--aurora-accent-soft)" : "transparent",
                color: active ? "var(--aurora-accent)" : "var(--aurora-fg3)",
                border: active ? "1px solid color-mix(in srgb, var(--aurora-accent) 30%, transparent)" : "1px solid transparent",
                fontWeight: active ? 600 : 450,
              }}
            >
              <Icon name={tab.icon} size={15} color={active ? "var(--aurora-accent)" : undefined} />
              <span>{tab.label}</span>
            </button>
          );
        })}
      </div>

      {/* Tab Panels */}
      {activeTab === "account" && <AccountTab />}
      {activeTab === "devices" && <DevicesView hideTopBar />}
      {activeTab === "collector" && <CollectorView hideTopBar />}
      {activeTab === "health" && <StatusView hideTopBar />}
      {activeTab === "admin" && <AdminPanelTab />}
    </div>
  );
}

function AccountTab() {
  const { user, token, logout, setUser } = useAuth();
  const { t } = useI18n();

  const [name, setName] = useState(user?.name || "");
  const [savingName, setSavingName] = useState(false);
  const [uploadingAvatar, setUploadingAvatar] = useState(false);
  const [profileMsg, setProfileMsg] = useState<{ type: "success" | "error"; text: string } | null>(null);
  const avatarInputRef = useRef<HTMLInputElement>(null);

  const [exporting, setExporting] = useState(false);
  const [importing, setImporting] = useState(false);
  const [includeLogs, setIncludeLogs] = useState(false);
  const [importFile, setImportFile] = useState<File | null>(null);
  const [importSummary, setImportSummary] = useState<ImportSummary | null>(null);
  const [errMsg, setErrMsg] = useState<string>("");
  const fileInputRef = useRef<HTMLInputElement>(null);

  useEffect(() => {
    if (user?.name !== undefined) {
      setName(user?.name || "");
    }
  }, [user?.name]);

  if (!user) return null;

  const handleAvatarFile = async (e: React.ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0];
    if (!file || !token) return;
    if (file.size > 2 * 1024 * 1024) {
      setProfileMsg({ type: "error", text: "头像文件大小不能超过 2MB" });
      return;
    }
    setProfileMsg(null);
    setUploadingAvatar(true);
    try {
      const updated = await api.uploadAvatar(token, file);
      setUser(updated);
      setProfileMsg({ type: "success", text: t.profile.saveSuccess });
    } catch (err: unknown) {
      setProfileMsg({ type: "error", text: err instanceof Error ? err.message : String(err) });
    } finally {
      setUploadingAvatar(false);
      if (avatarInputRef.current) avatarInputRef.current.value = "";
    }
  };

  const handleRemoveAvatar = async () => {
    if (!token) return;
    setProfileMsg(null);
    setUploadingAvatar(true);
    try {
      const updated = await api.deleteAvatar(token);
      setUser(updated);
      setProfileMsg({ type: "success", text: t.profile.saveSuccess });
    } catch (err: unknown) {
      setProfileMsg({ type: "error", text: err instanceof Error ? err.message : String(err) });
    } finally {
      setUploadingAvatar(false);
    }
  };

  const handleSaveProfile = async (e?: React.FormEvent) => {
    if (e) e.preventDefault();
    if (!token) return;
    setProfileMsg(null);
    setSavingName(true);
    try {
      const updated = await api.updateProfile(token, { name: name.trim() });
      setUser(updated);
      setProfileMsg({ type: "success", text: t.profile.saveSuccess });
    } catch (err: unknown) {
      setProfileMsg({ type: "error", text: err instanceof Error ? err.message : String(err) });
    } finally {
      setSavingName(false);
    }
  };

  const handleExport = async () => {
    if (!token) return;
    setErrMsg("");
    setExporting(true);
    try {
      const { blob, filename } = await api.exportData(token, includeLogs);
      const url = URL.createObjectURL(blob);
      const a = document.createElement("a");
      a.href = url;
      a.download = filename;
      document.body.appendChild(a);
      a.click();
      document.body.removeChild(a);
      setTimeout(() => URL.revokeObjectURL(url), 0);
    } catch (e: unknown) {
      setErrMsg(e instanceof Error ? e.message : String(e));
    } finally {
      setExporting(false);
    }
  };

  const handleImport = async () => {
    if (!token || !importFile) return;
    setErrMsg("");
    setImportSummary(null);
    setImporting(true);
    try {
      const result = await api.importData(token, importFile);
      setImportSummary(result);
      setImportFile(null);
      if (fileInputRef.current) fileInputRef.current.value = "";
    } catch (e: unknown) {
      setErrMsg(e instanceof Error ? e.message : String(e));
    } finally {
      setImporting(false);
    }
  };

  return (
    <div className="w-full">
      <SectionLabel>{t.profile.basicInfo || "基本信息"}</SectionLabel>
      <Glass padding={22} radius={20} style={{ marginBottom: 20 }}>
        {/* Avatar & Photo Actions */}
        <div style={{ display: "flex", alignItems: "center", gap: 20, paddingBottom: 20, borderBottom: "1px solid var(--aurora-border)" }}>
          <div
            style={{
              position: "relative",
              width: 76,
              height: 76,
              borderRadius: 9999,
              overflow: "hidden",
              background: "var(--aurora-primary-grad)",
              color: "#fff",
              display: "flex",
              alignItems: "center",
              justifyContent: "center",
              fontSize: 28,
              fontWeight: 600,
              flexShrink: 0,
              boxShadow: "0 4px 16px -4px rgba(124, 58, 237, 0.4)",
              border: "2px solid var(--aurora-border)",
            }}
          >
            {user.avatar_url ? (
              // eslint-disable-next-line @next/next/no-img-element
              <img
                src={user.avatar_url}
                alt={user.name || user.email}
                style={{ width: "100%", height: "100%", objectFit: "cover" }}
              />
            ) : (
              (user.name || user.email)[0]?.toUpperCase() || "?"
            )}
            {uploadingAvatar && (
              <div
                style={{
                  position: "absolute",
                  inset: 0,
                  background: "rgba(0,0,0,0.5)",
                  display: "flex",
                  alignItems: "center",
                  justifyContent: "center",
                  color: "#fff",
                  fontSize: 11,
                }}
              >
                <Icon name="refresh" size={18} style={{ animation: "spin 1s linear infinite" }} />
              </div>
            )}
          </div>

          <div style={{ flex: 1, minWidth: 0 }}>
            <div style={{ display: "flex", gap: 8, alignItems: "center", flexWrap: "wrap", marginBottom: 6 }}>
              <input
                ref={avatarInputRef}
                type="file"
                accept="image/png,image/jpeg,image/webp,image/gif"
                onChange={handleAvatarFile}
                style={{ display: "none" }}
              />
              <Btn
                type="button"
                size="sm"
                variant="glass"
                icon="camera"
                onClick={() => avatarInputRef.current?.click()}
                disabled={uploadingAvatar}
              >
                {uploadingAvatar ? t.profile.uploadingAvatar : t.profile.changeAvatar}
              </Btn>
              {user.avatar_url && (
                <Btn
                  type="button"
                  size="sm"
                  variant="ghost"
                  icon="trash"
                  onClick={handleRemoveAvatar}
                  disabled={uploadingAvatar}
                  style={{ color: "#DC2626" }}
                >
                  {t.profile.removeAvatar}
                </Btn>
              )}
            </div>
            <p style={{ margin: 0, fontSize: 12, color: "var(--aurora-fg4)" }}>
              {t.profile.avatarHint}
            </p>
          </div>
        </div>

        {/* Nickname row */}
        <form onSubmit={handleSaveProfile} style={{ padding: "14px 0", borderBottom: "1px solid var(--aurora-border)" }}>
          <div style={{ display: "flex", alignItems: "center", gap: 12 }}>
            <span style={{ fontSize: 13, color: "var(--aurora-fg3)", width: 70, flexShrink: 0 }}>
              {t.profile.name}
            </span>
            <div style={{ flex: 1, minWidth: 0 }}>
              <GhostInput
                value={name}
                onChange={(e) => setName(e.target.value)}
                placeholder={t.profile.nicknamePlaceholder}
                maxLength={50}
              />
            </div>
            <Btn
              type="submit"
              size="sm"
              icon="check"
              disabled={savingName || name === (user.name || "")}
            >
              {savingName ? t.profile.savingProfile : t.profile.saveProfile}
            </Btn>
          </div>
        </form>

        <Row label={t.profile.email} value={user.email} />
        <Row label={t.profile.role} valueNode={<Chip>{user.role}</Chip>} />
        <Row
          label={t.profile.status}
          valueNode={<Chip tone={user.status === "active" ? "success" : "warn"}>{user.status}</Chip>}
        />

        {profileMsg && (
          <div
            style={{
              marginTop: 14,
              padding: "8px 12px",
              borderRadius: 8,
              fontSize: 12,
              background: profileMsg.type === "success" ? "rgba(16,185,129,0.12)" : "rgba(239,68,68,0.12)",
              color: profileMsg.type === "success" ? "#10B981" : "#DC2626",
              display: "flex",
              alignItems: "center",
              gap: 6,
            }}
          >
            <Icon name={profileMsg.type === "success" ? "check" : "close"} size={14} />
            {profileMsg.text}
          </div>
        )}
      </Glass>

      <SectionLabel>{t.notify.title}</SectionLabel>
      <NotifySettings />

      <SectionLabel>{t.profile.backup}</SectionLabel>
      <Glass padding={22} radius={20} style={{ marginBottom: 20 }}>
        <p style={{ fontSize: 13, color: "var(--aurora-fg3)", margin: "0 0 14px" }}>
          {t.profile.backupDesc}
        </p>
        <label style={{ display: "flex", alignItems: "center", gap: 8, fontSize: 12, color: "var(--aurora-fg3)", marginBottom: 12 }}>
          <input
            type="checkbox"
            checked={includeLogs}
            onChange={(e) => setIncludeLogs(e.target.checked)}
          />
          {t.profile.includeLogs}
        </label>
        <Btn size="sm" icon="arrow_down" onClick={handleExport} disabled={exporting}>
          {exporting ? t.profile.exporting : t.profile.exportBtn}
        </Btn>

        <hr style={{ border: 0, borderTop: "1px solid var(--aurora-border)", margin: "18px 0" }} />

        <p style={{ fontSize: 13, color: "var(--aurora-fg3)", margin: "0 0 12px" }}>
          {t.profile.restoreDesc}
        </p>
        <input
          ref={fileInputRef}
          type="file"
          accept=".zip,application/zip"
          onChange={(e) => setImportFile(e.target.files?.[0] ?? null)}
          style={{ fontSize: 12, marginBottom: 12, display: "block" }}
        />
        <Btn size="sm" icon="arrow_up" onClick={handleImport} disabled={!importFile || importing}>
          {importing ? t.profile.importing : t.profile.importBtn}
        </Btn>

        {importSummary && (
          <div
            style={{
              marginTop: 14,
              padding: "10px 12px",
              borderRadius: 10,
              background: "rgba(16,185,129,0.10)",
              color: "var(--aurora-fg2)",
              fontSize: 12,
            }}
          >
            <strong>{t.profile.importSuccess}</strong>
            <ul style={{ margin: "6px 0 0 18px", padding: 0, lineHeight: 1.7 }}>
              {Object.entries(importSummary.counts).map(([k, v]) => (
                <li key={k}>
                  <code>{k}</code>: {v}
                </li>
              ))}
            </ul>
            {importSummary.warnings.length > 0 && (
              <details style={{ marginTop: 8 }}>
                <summary style={{ cursor: "pointer", color: "var(--aurora-fg3)" }}>
                  {t.profile.importWarnings} ({importSummary.warnings.length})
                </summary>
                <ul style={{ margin: "6px 0 0 18px" }}>
                  {importSummary.warnings.map((w, i) => (
                    <li key={i} style={{ color: "var(--aurora-fg4)" }}>{w}</li>
                  ))}
                </ul>
              </details>
            )}
          </div>
        )}

        {errMsg && (
          <div
            style={{
              marginTop: 14,
              padding: "10px 12px",
              borderRadius: 10,
              background: "rgba(239,68,68,0.10)",
              color: "#B91C1C",
              fontSize: 12,
            }}
          >
            {errMsg}
          </div>
        )}
      </Glass>

      <div style={{ textAlign: "right" }}>
        <Btn variant="ghost" size="sm" icon="log_out" onClick={logout}>
          {t.profile.logout}
        </Btn>
      </div>
    </div>
  );
}

function AdminPanelTab() {
  return (
    <Glass padding={28} radius={20} style={{ textAlign: "center" }}>
      <div
        style={{
          width: 56,
          height: 56,
          borderRadius: 16,
          margin: "0 auto 16px",
          background: "var(--aurora-brand-grad)",
          display: "flex",
          alignItems: "center",
          justifyContent: "center",
          boxShadow: "0 12px 40px -10px rgba(124,58,237,0.5)",
        }}
      >
        <Icon name="lock" size={26} style={{ color: "#fff" }} strokeWidth={2} />
      </div>
      <h3 style={{ margin: "0 0 8px", fontSize: 18, fontWeight: 600, color: "var(--aurora-fg1)" }}>
        管理员控制中心
      </h3>
      <p style={{ margin: "0 auto 20px", maxWidth: 440, fontSize: 13.5, color: "var(--aurora-fg3)", lineHeight: 1.6 }}>
        您拥有管理员权限，可以在管理控制台进行多用户账号审核、全量设备监管、系统同步状态分析与全局资源调配。
      </p>
      <Link href="/admin">
        <Btn icon="external_link" size="md">
          进入管理控制台 &rarr;
        </Btn>
      </Link>
    </Glass>
  );
}

function Row({
  label,
  value,
  valueNode,
}: {
  label: string;
  value?: string;
  valueNode?: React.ReactNode;
}) {
  return (
    <div
      style={{
        display: "flex",
        justifyContent: "space-between",
        alignItems: "center",
        padding: "10px 0",
        borderBottom: "1px solid var(--aurora-border)",
        gap: 12,
      }}
    >
      <span style={{ fontSize: 13, color: "var(--aurora-fg3)" }}>{label}</span>
      {valueNode ?? (
        <span style={{ fontSize: 13, color: "var(--aurora-fg1)", fontWeight: 500 }}>{value}</span>
      )}
    </div>
  );
}
