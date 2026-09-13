# Memento Collector (Dart / Flutter 纯原生采集器)

基于 **Dart / Flutter** 纯原生实现的 Memento 跨平台采集器与远程执行引擎，彻底摆脱 Python 环境依赖，提供毫秒级冷启动、极低内存占用与高可靠性常驻守护。

---

## 🌟 核心特性

1. **零 Python 依赖（Zero Dependency）**：
   - 纯 Dart 编写，无需在 Windows / Mac 上安装 Python 3.11+、无需配置 pip、环境变量或处理依赖冲突。
2. **界面 + 采集器一体化（All-in-One App）**：
   - 直接内置于 Memento 客户端（`mobile/`）中；
   - 提供「本机采集器」管理面板，一键启停、查看在线状态、本地已识别开发工具与实时控制台日志。
3. **双通道高可靠连接**：
   - **WebSocket 实时长连接**：毫秒级接收 `/api/tasks/ws/{device_id}` 派发指令，实时分块流式回传标准输出/错误（stdout/stderr），支持远程进程取消（`task_cancel`）；
   - **25秒自动应用层 Ping 保活**：后台持续刷新服务器数据库心跳，彻底根除设备休眠或断连误判。
4. **两用架构（GUI 与无头单文件 CLI 并存）**：
   - 可在 Flutter 桌面端带界面运行；
   - 也支持通过 `dart compile exe bin/collector.dart -o memento-collector` 编译为仅约 15MB 的纯单文件可执行程序，部署到无桌面的 Linux VPS、Docker 或 NAS 服务器。

---

## 🚀 使用指南

### 方式一：在 Flutter 客户端界面中运行（推荐日常电脑）

1. 启动 Memento 客户端（Windows / macOS / Android / iOS）：
   ```bash
   cd mobile
   flutter run -d macos    # 或 flutter run -d windows
   ```
2. 在侧边栏或底部导航栏点击 **「本机采集」** 图标；
3. 点击右上角或面板中的 **【启动】** 按钮：
   - 指示灯变为 🟢 **已连接服务器 (在线)**；
   - 自动检测本地已安装的开发工具（Claude Code、OpenAI Codex、Google Antigravity、Cursor、Obsidian）；
   - 实时控制台滚动显示心跳与文件增量变动。

---

### 方式二：无界面独立命令行运行（Headless CLI）

适用于 Linux VPS、NAS 或不需要界面的后台服务：

#### 直接运行脚本：
```bash
cd mobile
dart run bin/collector.dart
```

#### 常用命令：
```bash
dart run bin/collector.dart status    # 查看当前设备 ID、名称与连接配置
dart run bin/collector.dart setup     # 交互式配置服务器地址与 Token
dart run bin/collector.dart run       # 前台守护运行
```

#### 编译为单文件原生二进制（无需任何运行时）：
```bash
cd mobile
dart compile exe bin/collector.dart -o memento-collector
```
- 编译生成的 `memento-collector`（Windows 下为 `memento-collector.exe`）是一个自包含的独立二进制可执行文件；
- 移动到任意机器双击或作为系统服务运行即可，无需安装 Dart SDK 或 Python！

---

## 📁 代码架构

```
mobile/
├── bin/
│   └── collector.dart                 # 单文件无头 CLI 启动入口
├── lib/
│   └── collector/
│       ├── collector_controller.dart  # 采集器生命周期总控（启动、停止、状态分发）
│       ├── discovery/
│       │   └── tool_discovery_service.dart # Claude/Codex/Antigravity/Cursor/Obsidian 路径嗅探
│       ├── models/
│       │   ├── collector_config.dart  # 跨平台配置 (~/.memento/collector.json)
│       │   ├── task_message.dart      # WebSocket 任务、流式 Chunk、完成事件模型
│       │   └── tool_discovery.dart    # 工具与项目模型
│       ├── security/
│       │   └── sanitizer.dart         # API Key、Token 与超大 Base64 敏感数据过滤
│       └── services/
│           ├── file_watcher_service.dart # Directory.watch 增量文件监控与防抖
│           ├── ingest_client.dart     # HTTP 注册、心跳与文档上传
│           └── ws_task_client.dart    # WebSocket 实时任务执行、进程调用与流式回传
├── test/
│   └── collector/                     # 单元与集成测试套件
```
