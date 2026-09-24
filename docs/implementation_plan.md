# 实施计划 (Implementation Plan)

## 任务背景与核心目标
1. **提问流式响应“经常会出现请求异常”彻底解决**：
   - 解决用户使用 Ask / 远程设备控制时出现的 `HttpException: Connection closed while receiving data`。
   - 实施服务端多级流式保活注入（`: keepalive\n\n`）与客户端首包断连静默容灾重试。
2. **客户端 UI/UX 深度美化与视觉升级**：
   - 打造 **Aurora Glassmorphism 2.0** 极光暗色玻璃拟态质感。
   - 优化头部导航（分段胶囊 TabBar）、核心记忆树（Indent Guide 树状层级引导虚线、即时搜索过滤框、微光指标卡条）、叶子节点排版及做梦三层记忆金字塔可视化。

---

## 模块实施细则

### 阶段一：流式请求稳定性与网络容灾（已完成并发布 v1.0.49）
- [x] **服务端保活心跳注入**：
  - 在 [`server/server/api/ask.py`](file:///Users/haixingdong/dev/memento/server/server/api/ask.py) 中实现 `sse_keepalive_generator`。
  - 针对普通问答 `stream()`、协作调度 `agent_stream()`、直连设备 `_direct_agent_stream()` 注入 8s 心跳包，防止 Traefik / NAT 超时断连。
- [x] **客户端首包断连静默重试与友好提示**：
  - 在 [`mobile/lib/core/sse_client.dart`](file:///Users/haixingdong/dev/memento/mobile/lib/core/sse_client.dart) 中扩大重试作用域至流消费阶段。
  - 首包前断开自动静默重试 2 次；已接收内容中断连友好拼接降级提示；原始 `HttpException` 转译为中文友好说明。
- [x] **端到端测试与质量验证**：
  - 服务端 Pytest 84 项测试全部通过。
  - 客户端 Flutter Test 64 项测试全部通过。
- [x] **版本发布与 CI/CD 触发**：
  - 发布版本 `v1.0.49`（Git Tag `v1.0.49`），触发 GitHub Actions 构建 macOS、Windows、Linux 更新包及服务端镜像部署。
  - 主分支元数据已同步更新（Commit `e9df7f4`）。

---

### 阶段二：客户端 UI/UX 深度美化与视觉升级
- [x] **顶部导航与操作栏升维** ([`mobile/lib/ui/screens/memory_screen.dart`](file:///Users/haixingdong/dev/memento/mobile/lib/ui/screens/memory_screen.dart)):
  - 分段胶囊 TabBar (Segmented Capsule Tabs)：嵌入式毛玻璃胶囊切换器、动态 Badge 计数。
  - HUD 认知概览仪表盘 (Memory Metric Strip)：5 大维度（`/project`, `/architecture`, `/rules`, `/tools`, `/preference`）发光指标卡。
  - 树状视图即时搜索输入框：支持毫秒级过滤工程名、标识与内容。
- [x] **核心记忆树结构深度美化**:
  - 顶层五大维度 Hero 卡片专属微发光渐变色标与 Icon。
  - 39 个项目工程节点展示业务类型专属彩色前缀、中文友好名、Monospace 标识及关联文档/事实数徽章。
  - 绘制树状层级引导连接虚线（Indent Guide Lines）。
  - 记忆卡片左侧添加 3.5px 维度专属色彩高亮条，精细排版与快捷微交互。
- [x] **梦境与三层认知记忆金字塔可视化**:
  - 呈现 L1 工作会话 -> L2 每日研报 -> L3 长期核心准则的三层记忆金字塔。
  - 极光呼吸渐变触发按钮。

---

## 验收标准与交付物
1. **稳定性指标**：
   - 长时间模型思考（> 30s）不再触发 `HttpException: Connection closed while receiving data`。
   - 弱网波动下首包前自动静默恢复，无刺眼红色报错气泡。
2. **体验指标**：
   - 记忆树层级分明，视觉清晰，支持毫秒级快速搜索定位。
   - 桌面端多平台适配良好（macOS / Windows / Web）。
