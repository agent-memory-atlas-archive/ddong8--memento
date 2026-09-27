import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme/aurora_theme.dart';
import '../../state/auth_state.dart';
import '../../models/device.dart';
import '../../state/device_state.dart';
import '../widgets/glass_card.dart';
import '../widgets/aurora_shimmer.dart';
import '../widgets/aurora_empty_state.dart';
import '../widgets/notify_settings_sheet.dart';
import '../../core/api_client.dart';
import 'health_screen.dart';

class DevicesScreen extends ConsumerWidget {
  const DevicesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final deviceState = ref.watch(deviceProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('设备'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, size: 20),
            tooltip: '刷新设备列表',
            onPressed: () {
              ref.read(deviceProvider.notifier).loadDevices();
            },
          ),
          const _HealthButton(),
          IconButton(
            icon: const Icon(Icons.notifications_none_rounded, size: 20),
            tooltip: '手机推送',
            onPressed: () => showNotifySettingsSheet(context),
          ),
          IconButton(
            icon: const Icon(Icons.logout, size: 20),
            tooltip: '退出登录',
            onPressed: () {
              ref.read(authProvider.notifier).logout();
            },
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => ref.read(deviceProvider.notifier).loadDevices(),
        color: AuroraColors.accent,
        child: deviceState.isLoading && deviceState.devices.isEmpty
            ? const AuroraListSkeleton(count: 3)
            : deviceState.devices.isEmpty
                ? ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    children: [
                      const SizedBox(height: 48),
                      AuroraEmptyState(
                        icon: Icons.devices_other_rounded,
                        title: '暂无已纳管的终端设备',
                        description: 'Memento 支持跨设备远程代码调度与跨端编程记忆共享。\n在您的开发电脑上运行采集守护进程，设备将在此自动呈现。',
                        codeSnippet: 'memento start',
                        actionLabel: '刷新设备列表',
                        onAction: () => ref.read(deviceProvider.notifier).loadDevices(),
                      ),
                    ],
                  )
            : ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: deviceState.devices.length,
                itemBuilder: (context, index) {
                  final dev = deviceState.devices[index];
                  final isOnline = dev.isOnline;

                  return Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    child: GlassCard(
                      padding: const EdgeInsets.all(16),
                      child: _DeviceCardBody(dev: dev, isOnline: isOnline),
                    ),
                  );
                },
              ),
      ),
    );
  }
}

const _toolNames = {
  'claude_code': 'Claude Code',
  'codex': 'Codex',
  'antigravity': 'Antigravity',
  'cursor': 'Cursor',
  'hermes': 'Hermes',
  'obsidian': 'Obsidian',
  'openclaw': 'OpenClaw',
  'windsurf': 'Windsurf',
  'cline': 'Cline',
};

class _DeviceCardBody extends StatelessWidget {
  final Device dev;
  final bool isOnline;

  const _DeviceCardBody({required this.dev, required this.isOnline});

  @override
  Widget build(BuildContext context) {
    final (name, platform) = splitDeviceName(dev.name);
    final meta = [
      if (platform != null) platform,
      if (dev.collectorVersion != null) 'v${dev.collectorVersion}',
      if (dev.documentCount > 0) '${dev.documentCount} 条记忆',
    ].join(' · ');
    final tools = dev.tools;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            // Online devices get a soft halo so they read at a glance.
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isOnline ? AuroraColors.success : AuroraColors.fg4,
                boxShadow: isOnline
                    ? [BoxShadow(color: AuroraColors.success.withValues(alpha: 0.16), spreadRadius: 3)]
                    : null,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                name,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  letterSpacing: -0.2,
                  color: isOnline ? AuroraColors.fg1 : AuroraColors.fgCode,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Container(
              height: 22,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: isOnline ? AuroraColors.successSoft : AuroraColors.chip,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                isOnline ? '在线' : '离线',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: isOnline ? AuroraColors.success : AuroraColors.fg3,
                ),
              ),
            ),
          ],
        ),
        if (meta.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text(meta, style: const TextStyle(fontSize: 13, color: AuroraColors.fg2)),
        ],
        if (tools.isNotEmpty) ...[
          const SizedBox(height: 12),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final tool in tools)
                Container(
                  height: 24,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  decoration: BoxDecoration(
                    color: AuroraColors.chip,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Center(
                    widthFactor: 1,
                    child: Text(
                      _toolNames[tool] ?? tool,
                      style: const TextStyle(fontSize: 12, color: AuroraColors.fg2),
                    ),
                  ),
                ),
            ],
          ),
        ],
        const SizedBox(height: 12),
        const Divider(height: 1, thickness: 1, color: AuroraColors.chip),
        const SizedBox(height: 12),
        Tooltip(
          message: dev.deviceId,
          child: Text(
            '最近心跳 ${dev.heartbeatText}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 12, color: AuroraColors.fg3),
          ),
        ),
      ],
    );
  }
}

/// Opens the health page; a dot shows when something needs a look.
class _HealthButton extends StatefulWidget {
  const _HealthButton();

  @override
  State<_HealthButton> createState() => _HealthButtonState();
}

class _HealthButtonState extends State<_HealthButton> {
  String? _level;

  @override
  void initState() {
    super.initState();
    _check();
  }

  Future<void> _check() async {
    try {
      final data = await ApiClient().getHealthOverview();
      if (mounted) setState(() => _level = data['level'] as String?);
    } catch (_) {
      // An older server without the endpoint just shows no dot.
    }
  }

  @override
  Widget build(BuildContext context) {
    final dot = switch (_level) {
      'error' => AuroraColors.danger,
      'warn' => AuroraColors.warn,
      _ => null,
    };
    return IconButton(
      tooltip: '系统健康',
      onPressed: () async {
        await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const HealthScreen()));
        _check();
      },
      icon: Stack(
        clipBehavior: Clip.none,
        children: [
          const Icon(Icons.monitor_heart_outlined, size: 20),
          if (dot != null)
            Positioned(
              right: -2,
              top: -2,
              child: Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: dot,
                  shape: BoxShape.circle,
                  border: Border.all(color: AuroraColors.bg, width: 1.5),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
