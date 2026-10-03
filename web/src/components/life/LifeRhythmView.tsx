import { useEffect, useRef, useState } from "react";
import { api, type DailyLifeRhythm } from "@/lib/api-client";
import { Glass, Btn, Chip, SectionLabel } from "@/components/aurora/primitives";
import { Icon } from "@/components/aurora/Icon";

export function LifeRhythmView() {
  const [rhythms, setRhythms] = useState<DailyLifeRhythm[]>([]);
  const [loading, setLoading] = useState(true);
  const [generatingAdvice, setGeneratingAdvice] = useState(false);
  const [populating, setPopulating] = useState(false);
  const [clearing, setClearing] = useState(false);
  const [parsingImage, setParsingImage] = useState(false);
  const [feedback, setFeedback] = useState<{ text: string; error?: boolean } | null>(null);
  const [selectedDayIndex, setSelectedDayIndex] = useState(0);
  const fileInputRef = useRef<HTMLInputElement | null>(null);

  const loadData = async () => {
    try {
      setLoading(true);
      const data = await api.getLifeRhythm(7);
      setRhythms(data);
    } catch (e) {
      console.error("Failed to load life rhythms", e);
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => {
    loadData();
  }, []);

  const handleGenerateAdvice = async (dateStr?: string) => {
    try {
      setGeneratingAdvice(true);
      await api.getLifeAdvice(dateStr);
      await loadData();
    } catch (e) {
      alert("AI 决策建议生成失败，请确认后端 AI 服务配置");
    } finally {
      setGeneratingAdvice(false);
    }
  };

  const handlePopulateSample = async () => {
    try {
      setPopulating(true);
      await api.populateSampleLifeRhythm();
      await loadData();
      setFeedback({ text: "✨ 已载入示例作息与时间分配数据！" });
      setTimeout(() => setFeedback(null), 3000);
    } catch (e) {
      alert("生成示例数据失败");
    } finally {
      setPopulating(false);
    }
  };

  const handleClearData = async () => {
    if (!confirm("确定要清空当前的作息与 App 耗时数据吗？清空后将从真实设备全新采集。")) return;
    try {
      setClearing(true);
      await api.clearLifeRhythms();
      await loadData();
      setFeedback({ text: "🗑️ 已清空作息数据，等待设备真实数据同步..." });
      setTimeout(() => setFeedback(null), 3000);
    } catch (e) {
      alert("清空数据失败");
    } finally {
      setClearing(false);
    }
  };

  const handleFileChange = async (e: React.ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0];
    if (!file) return;
    try {
      setParsingImage(true);
      setFeedback(null);
      const reader = new FileReader();
      const base64Promise = new Promise<string>((resolve, reject) => {
        reader.onload = () => resolve(reader.result as string);
        reader.onerror = reject;
      });
      reader.readAsDataURL(file);
      const base64 = await base64Promise;

      const res = await api.parseScreenTimeImage(base64);
      await loadData();
      setFeedback({
        text: `✅ 成功解析屏幕时间截图！已识别 ${res.apps_count} 个应用，总屏幕时长 ${Math.floor(res.total_screen_minutes / 60)}h ${res.total_screen_minutes % 60}m。`,
      });
      setTimeout(() => setFeedback(null), 5000);
    } catch (err: any) {
      setFeedback({
        text: `❌ 截图解析失败: ${err.message || "请确保截图中清晰展示了应用时长"}`,
        error: true,
      });
    } finally {
      setParsingImage(false);
      if (fileInputRef.current) fileInputRef.current.value = "";
    }
  };


  if (loading) {
    return (
      <div className="py-12 text-center text-sm text-[var(--aurora-fg4)]">
        加载作息与时间分配数据...
      </div>
    );
  }

  const currentDay = rhythms[selectedDayIndex] || null;

  return (
    <div className="space-y-6">
      {/* Top Banner & Quick Actions */}
      <Glass className="p-6">
        <div className="flex flex-col md:flex-row md:items-center justify-between gap-4">
          <div className="flex items-start gap-3.5">
            <div
              style={{
                width: 44,
                height: 44,
                borderRadius: 14,
                background: "linear-gradient(135deg, #3B82F6 0%, #8B5CF6 100%)",
                display: "flex",
                alignItems: "center",
                justifyContent: "center",
                color: "#fff",
                boxShadow: "0 4px 16px -2px rgba(99,102,241,0.4)",
                flexShrink: 0,
              }}
            >
              <Icon name="clock" size={22} />
            </div>
            <div>
              <div className="flex items-center gap-2">
                <h3 className="text-base font-semibold text-[var(--aurora-fg1)]">
                  生活作息与时间精力分配
                </h3>
                <span className="text-[10px] bg-indigo-500/10 text-indigo-400 border border-indigo-500/20 px-2 py-0.5 rounded-full font-semibold">
                  AI 决策顾问
                </span>
              </div>
              <p className="text-xs text-[var(--aurora-fg3)] mt-1.5 leading-relaxed max-w-xl">
                全天候记住您每日的起床就寝、工作专注与手机各 App 耗时分布，让 AI 深入您的生活节律，提供量身定制的生活与精力决策建议。
              </p>
            </div>
          </div>

          <div className="flex items-center gap-2 flex-wrap">
            <input
              type="file"
              ref={fileInputRef}
              onChange={handleFileChange}
              accept="image/*"
              style={{ display: "none" }}
            />

            <Btn
              variant="glass"
              onClick={() => fileInputRef.current?.click()}
              disabled={parsingImage}
              className="text-xs py-1.5"
            >
              {parsingImage ? "AI 视觉解析中..." : "📸 手机截图智能解析"}
            </Btn>

            {rhythms.length > 0 && (
              <Btn
                variant="glass"
                onClick={handleClearData}
                disabled={clearing}
                className="text-xs py-1.5 text-rose-500 hover:text-rose-600"
              >
                {clearing ? "清空中..." : "🗑️ 清空数据"}
              </Btn>
            )}

            {rhythms.length === 0 && (
              <Btn
                variant="glass"
                onClick={handlePopulateSample}
                disabled={populating}
                className="text-xs py-1.5"
              >
                {populating ? "生成中..." : "✨ 体验示例作息数据"}
              </Btn>
            )}

            {currentDay && (
              <Btn
                variant="primary"
                onClick={() => handleGenerateAdvice(currentDay.date)}
                disabled={generatingAdvice}
                className="text-xs py-1.5"
              >
                {generatingAdvice ? "AI 深度推演中..." : "💡 重新推演决策建议"}
              </Btn>
            )}
          </div>
        </div>

        {feedback && (
          <div
            className="mt-4 p-3 rounded-xl text-xs font-medium transition-all"
            style={{
              background: feedback.error ? "rgba(239, 68, 68, 0.1)" : "rgba(16, 185, 129, 0.1)",
              color: feedback.error ? "#EF4444" : "#10B981",
              border: `1px solid ${feedback.error ? "rgba(239, 68, 68, 0.25)" : "rgba(16, 185, 129, 0.25)"}`,
            }}
          >
            {feedback.text}
          </div>
        )}
      </Glass>


      {/* Days Selector Tabs */}
      {rhythms.length > 0 && (
        <div className="flex items-center gap-2 overflow-x-auto no-scrollbar pb-1">
          {rhythms.map((r, idx) => {
            const active = idx === selectedDayIndex;
            return (
              <button
                key={r.id}
                type="button"
                onClick={() => setSelectedDayIndex(idx)}
                className="px-3.5 py-2 rounded-xl text-xs font-medium transition-all cursor-pointer whitespace-nowrap"
                style={{
                  background: active ? "var(--aurora-accent-soft)" : "var(--aurora-chip)",
                  color: active ? "var(--aurora-accent)" : "var(--aurora-fg3)",
                  border: active
                    ? "1px solid color-mix(in srgb, var(--aurora-accent) 30%, transparent)"
                    : "1px solid var(--aurora-border)",
                  fontWeight: active ? 600 : 450,
                }}
              >
                📅 {r.date} {idx === 0 ? "（今天）" : ""}
              </button>
            );
          })}
        </div>
      )}

      {currentDay ? (
        <div className="grid grid-cols-1 lg:grid-cols-12 gap-6">
          {/* Left Column: Sleep & Time Stat Metrics (7 cols) */}
          <div className="lg:col-span-7 space-y-6">
            {/* Sleep Rhythm Grid */}
            <div className="grid grid-cols-2 sm:grid-cols-4 gap-3">
              <div className="p-3.5 rounded-2xl bg-[var(--aurora-card)] border border-[var(--aurora-border)]">
                <div className="text-[11px] text-[var(--aurora-fg4)] mb-1">🌅 起床时间</div>
                <div className="text-base font-bold text-[var(--aurora-fg1)] font-mono">
                  {currentDay.wakeup_time || "未记录"}
                </div>
              </div>

              <div className="p-3.5 rounded-2xl bg-[var(--aurora-card)] border border-[var(--aurora-border)]">
                <div className="text-[11px] text-[var(--aurora-fg4)] mb-1">🌙 入睡时间</div>
                <div className="text-base font-bold text-[var(--aurora-fg1)] font-mono">
                  {currentDay.bedtime || "未记录"}
                </div>
              </div>

              <div className="p-3.5 rounded-2xl bg-[var(--aurora-card)] border border-[var(--aurora-border)]">
                <div className="text-[11px] text-[var(--aurora-fg4)] mb-1">💤 睡眠时长</div>
                <div className="text-base font-bold text-indigo-400 font-mono">
                  {currentDay.sleep_hours ? `${currentDay.sleep_hours} 小时` : "未知"}
                </div>
              </div>

              <div className="p-3.5 rounded-2xl bg-[var(--aurora-card)] border border-[var(--aurora-border)]">
                <div className="text-[11px] text-[var(--aurora-fg4)] mb-1">📱 总屏幕时长</div>
                <div className="text-base font-bold text-[var(--aurora-accent)] font-mono">
                  {Math.floor(currentDay.total_screen_minutes / 60)}h {currentDay.total_screen_minutes % 60}m
                </div>
              </div>
            </div>

            {/* Time Allocation (Work vs Distraction vs Social) */}
            <Glass className="p-5">
              <div className="flex items-center justify-between mb-4">
                <SectionLabel>精力分配结构 (专注 vs 娱乐分心)</SectionLabel>
                <div className="flex items-center gap-3 text-xs">
                  <span className="flex items-center gap-1.5 text-blue-400">
                    <span className="w-2.5 h-2.5 rounded-full bg-blue-500 inline-block" /> 生产力工作 (
                    {currentDay.productive_minutes}m)
                  </span>
                  <span className="flex items-center gap-1.5 text-amber-400">
                    <span className="w-2.5 h-2.5 rounded-full bg-amber-500 inline-block" /> 社交娱乐 (
                    {currentDay.distraction_minutes}m)
                  </span>
                </div>
              </div>

              {/* Progress Ratio Bar */}
              {currentDay.total_screen_minutes > 0 && (
                <div className="w-full h-3 rounded-full bg-[var(--aurora-chip)] overflow-hidden flex mb-5 border border-[var(--aurora-border)]">
                  <div
                    style={{
                      width: `${(currentDay.productive_minutes / currentDay.total_screen_minutes) * 100}%`,
                      background: "linear-gradient(90deg, #3B82F6, #6366F1)",
                    }}
                    title="工作专注时长"
                  />
                  <div
                    style={{
                      width: `${(currentDay.distraction_minutes / currentDay.total_screen_minutes) * 100}%`,
                      background: "linear-gradient(90deg, #F59E0B, #EF4444)",
                    }}
                    title="娱乐与分心时长"
                  />
                </div>
              )}

              {/* Detailed App Usage Breakdown */}
              <div className="space-y-3">
                <div className="text-xs font-semibold text-[var(--aurora-fg2)] mb-2">
                  各 App 停留耗时排行 (Top Applications)
                </div>
                {currentDay.app_usages.length === 0 ? (
                  <div className="py-4 text-center text-xs text-[var(--aurora-fg4)]">暂无具体 App 耗时明细</div>
                ) : (
                  currentDay.app_usages.map((app, i) => {
                    const pct = currentDay.total_screen_minutes
                      ? Math.round((app.minutes / currentDay.total_screen_minutes) * 100)
                      : 0;
                    const isWork = app.category === "work" || app.category === "reading";
                    return (
                      <div
                        key={i}
                        className="flex items-center justify-between text-xs p-2.5 rounded-xl bg-[var(--aurora-chip)] border border-[var(--aurora-border)]"
                      >
                        <div className="flex items-center gap-2.5 min-w-0">
                          <span className="text-sm">
                            {isWork ? "💻" : app.category === "social" ? "💬" : "🎬"}
                          </span>
                          <span className="font-medium text-[var(--aurora-fg1)] truncate max-w-[140px] sm:max-w-[200px]">
                            {app.name}
                          </span>
                          <span
                            style={{
                              fontSize: 9.5,
                              padding: "1px 5px",
                              borderRadius: 4,
                              background: isWork ? "rgba(59,130,246,0.15)" : "rgba(245,158,11,0.15)",
                              color: isWork ? "#60A5FA" : "#FBBF24",
                            }}
                          >
                            {isWork ? "生产力" : app.category === "social" ? "社交" : "娱乐"}
                          </span>
                        </div>
                        <div className="flex items-center gap-3 text-right">
                          <span className="text-[var(--aurora-fg4)] text-[11px]">{pct}%</span>
                          <span className="font-mono font-semibold text-[var(--aurora-fg1)] min-w-[55px]">
                            {Math.floor(app.minutes / 60) > 0 ? `${Math.floor(app.minutes / 60)}h ` : ""}
                            {app.minutes % 60}m
                          </span>
                        </div>
                      </div>
                    );
                  })
                )}
              </div>
            </Glass>
          </div>

          {/* Right Column: AI Professional Life Advisor (5 cols) */}
          <div className="lg:col-span-5">
            <Glass className="p-5 h-full flex flex-col justify-between">
              <div>
                <div className="flex items-center gap-2 mb-3">
                  <span className="text-lg">🧠</span>
                  <SectionLabel>AI 生活与精力决策导师 (Advisor)</SectionLabel>
                </div>

                {currentDay.ai_advice ? (
                  <div
                    className="text-xs leading-relaxed text-[var(--aurora-fg2)] whitespace-pre-wrap p-4 rounded-xl font-sans"
                    style={{
                      background: "rgba(124,58,237,0.04)",
                      border: "1px solid rgba(124,58,237,0.2)",
                    }}
                  >
                    {currentDay.ai_advice}
                  </div>
                ) : (
                  <div className="py-12 text-center text-xs text-[var(--aurora-fg4)] border border-dashed border-[var(--aurora-border)] rounded-xl">
                    <p className="mb-3">尚未对当天作息与时间分配进行推演分析。</p>
                    <Btn
                      variant="primary"
                      onClick={() => handleGenerateAdvice(currentDay.date)}
                      disabled={generatingAdvice}
                      className="text-xs py-1.5"
                    >
                      {generatingAdvice ? "正在分析中..." : "💡 立即生成 AI 决策建议"}
                    </Btn>
                  </div>
                )}
              </div>

              {/* Data Sync Channels Info */}
              <div className="mt-6 pt-4 border-t border-[var(--aurora-border)] text-[11px] text-[var(--aurora-fg4)] space-y-2">
                <div className="font-semibold text-[var(--aurora-fg2)]">📱 手机与电脑如何自动感知？</div>
                <div className="leading-relaxed">
                  • <b className="text-[var(--aurora-fg2)]">Mac 桌面端</b>：已内置原生秒级前台窗口探针，自动无感统计 Cursor、VS Code、Chrome、微信等活跃应用耗时。
                </div>
                <div className="leading-relaxed">
                  • <b className="text-[var(--aurora-fg2)]">iPhone 手机</b>：由于 iOS 沙盒限制，支持点击顶部「📸 手机截图智能解析」上传“设置 - 屏幕使用时间”截图（AI 视觉秒级提取真实数据），或配置 iOS 快捷指令定时同步。
                </div>
                <div className="leading-relaxed">
                  • <b className="text-[var(--aurora-fg2)]">Android 手机</b>：开启 Memento 移动端「应用使用情况」权限即可全自动后台读取各 App 时长。
                </div>
              </div>
            </Glass>
          </div>
        </div>
      ) : (
        <div className="py-16 text-center text-sm text-[var(--aurora-fg4)] border border-dashed border-[var(--aurora-border)] rounded-2xl space-y-4">
          <div className="text-3xl">📱 💻</div>
          <p className="max-w-md mx-auto text-xs text-[var(--aurora-fg3)] leading-relaxed">
            暂无作息与屏幕使用时间数据。桌面端已启动实时前台应用监测；手机端可直接上传屏幕使用时间截图，或载入示例数据体验。
          </p>
          <div className="flex items-center justify-center gap-3 flex-wrap">
            <Btn
              variant="primary"
              onClick={() => fileInputRef.current?.click()}
              disabled={parsingImage}
              className="text-xs"
            >
              {parsingImage ? "AI 视觉解析中..." : "📸 上传手机截图解析"}
            </Btn>
            <Btn
              variant="glass"
              onClick={handlePopulateSample}
              disabled={populating}
              className="text-xs"
            >
              {populating ? "生成中..." : "✨ 一键载入真实示例数据体验"}
            </Btn>
          </div>
        </div>
      )}

    </div>
  );
}
