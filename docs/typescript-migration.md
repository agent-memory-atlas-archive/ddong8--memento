# 客户端迁移到 TypeScript

目标：客户端和工具链统一成 TypeScript，参考 [Paseo](https://github.com/getpaseo/paseo) 的做法（守护进程 + 多端客户端 + 共享协议包）。服务端和向量服务继续用 Python（语言统一的主要好处——共享类型——从服务端的 OpenAPI 生成即可拿到；向量模型只能跑在 Python 里）。

迁移期间 Flutter 版照常可用，新版功能对齐、验证通过后再切换。

## 目标结构

```
package.json            npm workspaces 根
packages/core           @memento/core：从 OpenAPI 生成的类型、API 客户端、提问 SSE 流、任务事件
packages/daemon         @memento/daemon：本机守护进程（采集、派活执行、画像/技能注入、MCP）
apps/desktop            Electron 桌面端：拉起守护进程，窗口里是网页端界面
apps/mobile             Expo 手机端（iOS / Android）
web                     Next.js 网页端（同时是桌面端的界面）
server、embedding       Python，不动
```

## 阶段

### 阶段 1：共享包与工程基础
- [x] 根目录 npm workspaces；网页镜像改成以仓库根为构建上下文
- [x] `@memento/core`：从服务端 OpenAPI 生成类型（`npm run gen:api`），手写的任务事件、提问流事件类型
- [x] 跨端 API 客户端（openapi-fetch）和提问 SSE 流（断线按 last-event-id 续接、空闲 30 秒判定断线、未送达的发送用同一个 request_id 重试，与 Flutter 版一致）
- [x] CI：core 类型检查与测试、网页类型检查与构建

### 阶段 2：守护进程 + Electron 桌面端
守护进程（移植 Flutter 里的采集端，约 6 千行 Dart）：
- [ ] 配置与设备注册（沿用 `~/.memento/collector.json`，老用户无感切换）
- [ ] 工具发现、文件监听、脱敏、增量上传
- [ ] 画像注入、技能注入
- [ ] 派活执行：Claude stream-json / Codex --json 结构化事件、中途插话、独立分支、危险操作 hook
- [ ] P2P 媒体服务、开机自启
- [ ] 本机接口：给桌面端界面查看状态、日志、控制采集

网页端补齐 Flutter 版已有、网页没有的功能：
- [ ] 系统健康、学习效果
- [ ] 纠正学习（待确认规矩）、技能、待办
- [ ] 任务过程时间线、中途插话、独立分支开关
- [ ] 推送设置、做梦分层、检索评测
- [ ] 本机采集页（只在桌面端显示，通过守护进程）

Electron 桌面端：
- [ ] 主进程拉起守护进程、托盘、预加载桥（界面访问本机能力）
- [ ] 自动更新（GitHub Releases）、CI 打包 macOS / Windows / Linux
- [ ] 从 Flutter 桌面版迁移的提示与说明

### 阶段 3：MCP 服务改 TS
- [ ] 用官方 TS MCP SDK 移植 `mcp_server`（约 2 千行 Python）
- [ ] 分发方式：随桌面端提供，守护进程在本机提供 MCP 接口，免去单独安装

### 阶段 4：Expo 手机端
- [ ] 提问（含任务卡片）、记忆库、设备、日报待办、系统健康、推送设置
- [ ] 复用 `@memento/core`
- [ ] iOS 仍由本机 Xcode 构建；Android 由 CI 构建

### 收尾
- [ ] 清理不再使用的代码（旧 Python 采集器等，删除前逐个确认）
- [ ] Flutter 版下线说明

## 进度记录

| 日期 | 阶段 | 内容 |
|---|---|---|
| 2026-09-28 | — | 定下方案 |
| 2026-09-28 | 1 | workspaces + @memento/core（9 个测试）；网页镜像按新方式在本地模拟构建并启动验证 |
