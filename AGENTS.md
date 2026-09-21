# Memento Project - Agent Guidelines & Architecture Rules

## 自动更新发布与升级规范（重要铁律）

### 1. 桌面端自更新安装包格式
- **Windows**: **必须** 使用 `.zip` 格式（如 `Memento-windows-x64.zip`），**严禁** 在自动更新接口中下发 `setup.exe`！
  - **核心原因**：客户端原生内置针对 `.zip` 的在位热替换机制（`_performInPlaceReplacement`）。它支持目录权限检测、在受保护目录（如 `C:\Program Files`）下自动调用 `powershell.exe -Verb RunAs` 触发 UAC 提权，并使用 `robocopy` 增量覆盖。
  - **踩坑记录**：历史曾误将 Windows 升级包切换为 `setup.exe`，导致已发布的旧版本客户端在后台通过隐藏脚本静默调用时缺失 `-Verb RunAs` 提权，安装被 Windows 拒绝直接退出，随后脚本盲目拉起老版本并自删安装包，造成**“升级 -> 重启仍为旧版 -> 再次提示升级”的无限死循环**。
- **macOS**: **必须** 使用 `.zip` 格式（如 `Memento-macos-arm64.zip`），解压后通过 `osascript` 提权替换 `/Applications/Memento.app`。
- **Linux**: 支持 `.tar.gz`（解压就地覆盖）与 `.deb`。

### 2. 发布元数据“三位一体”强制校验
发布新版本时，以下三处的元数据必须完全一致，严禁人工猜测或填充假数据：
1. `data/updates/version.json` 中的 `asset_name`、`size`（精确到字节）、`sha256`。
2. GitHub Release 实际上传的 Release Assets 对应文件名与字节大小。
3. 服务端 `server/server/api/updates.py` 的平台匹配优先级：
   - Windows 平台**首选匹配 `.zip`**，备选 `.exe`/`.msi`。
   - macOS 平台**首选匹配 `.zip`**，备选 `.dmg`。

### 3. CI 构建版本号注入
- Flutter 桌面端打包时，必须通过 `--dart-define=APP_VERSION=$VERSION` 将版本号注入到二进制中。
- 确保应用运行时的 `PackageInfo` / `UpdateService.initVersion()` 能够精准识别当前实际版本，杜绝因版本号识别落后导致的假更新循环。

### 4. 进程清理保障
- 在执行在位热更覆盖前，必须彻底清理任何常驻后台的子进程（如 `memento-collector*`），防止 Windows 上 DLL 或 EXE 文件句柄被占用导致覆盖失败。
