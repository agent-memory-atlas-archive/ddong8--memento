import 'package:flutter/material.dart';
import '../../collector/collector_controller.dart';
import '../../core/theme/aurora_theme.dart';
import '../widgets/glass_card.dart';

/// Screen for managing and monitoring the local device collector.
class CollectorScreen extends StatefulWidget {
  final CollectorController controller;

  const CollectorScreen({super.key, required this.controller});

  @override
  State<CollectorScreen> createState() => _CollectorScreenState();
}

class _CollectorScreenState extends State<CollectorScreen> {
  final ScrollController _logScrollController = ScrollController();
  bool _autoScroll = true;

  @override
  void dispose() {
    _logScrollController.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    if (_autoScroll && _logScrollController.hasClients) {
      _logScrollController.animateTo(
        _logScrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<CollectorStatus>(
      stream: widget.controller.statusStream,
      initialData: widget.controller.currentStatus,
      builder: (context, snapshot) {
        final status = snapshot.data ?? widget.controller.currentStatus;
        WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());

        return Scaffold(
          appBar: AppBar(
            title: const Text('本机采集器 (Local Collector)'),
            actions: [
              IconButton(
                icon: Icon(
                  status.isRunning ? Icons.stop_circle_outlined : Icons.play_circle_fill,
                  color: status.isRunning ? Colors.redAccent : AuroraColors.accent,
                ),
                tooltip: status.isRunning ? '停止采集器' : '启动采集器',
                onPressed: () {
                  if (status.isRunning) {
                    widget.controller.stop();
                  } else {
                    widget.controller.start();
                  }
                },
              ),
            ],
          ),
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // Status Card
              GlassCard(
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 12,
                          height: 12,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: status.isOnline
                                ? const Color(0xFF10B981)
                                : (status.isRunning ? Colors.amber : Colors.redAccent),
                            boxShadow: [
                              if (status.isOnline)
                                const BoxShadow(
                                  color: Color(0xFF10B981),
                                  blurRadius: 8,
                                  spreadRadius: 1,
                                ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 10),
                        Text(
                          status.isOnline
                              ? '已连接服务器 (在线)'
                              : (status.isRunning ? '正在连接服务器...' : '采集器未运行'),
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: AuroraColors.fg1,
                          ),
                        ),
                        const Spacer(),
                        ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: status.isRunning ? Colors.red.withAlpha(40) : AuroraColors.accent,
                            foregroundColor: status.isRunning ? Colors.redAccent : Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                          onPressed: () {
                            if (status.isRunning) {
                              widget.controller.stop();
                            } else {
                              widget.controller.start();
                            }
                          },
                          icon: Icon(status.isRunning ? Icons.stop : Icons.play_arrow, size: 16),
                          label: Text(status.isRunning ? '停止' : '启动'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Text(
                      '设备名称: ${status.deviceName}',
                      style: const TextStyle(fontSize: 13, color: AuroraColors.fg2),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '服务器地址: ${status.serverUrl.isEmpty ? "未配置" : status.serverUrl}',
                      style: const TextStyle(fontSize: 13, color: AuroraColors.fg3),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 16),

              // Discovered Tools
              Text(
                '已检测到的本地开发工具 (${status.tools.length})',
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AuroraColors.fg2),
              ),
              const SizedBox(height: 8),
              if (status.tools.isEmpty)
                const GlassCard(
                  padding: EdgeInsets.all(16),
                  child: Center(
                    child: Text('暂未检测到支持的工具或采集器未启动', style: TextStyle(color: AuroraColors.fg4, fontSize: 13)),
                  ),
                )
              else
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: status.tools.values.map((tool) {
                    return Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: AuroraColors.chip,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: AuroraColors.border),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.code, size: 16, color: AuroraColors.accent),
                          const SizedBox(width: 6),
                          Text(tool.name, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: AuroraColors.accent.withAlpha(30),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              '${tool.projects.length} 个项目',
                              style: const TextStyle(fontSize: 11, color: AuroraColors.accent),
                            ),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                ),

              const SizedBox(height: 20),

              // Realtime Logs
              Row(
                children: [
                  const Text(
                    '实时运行日志',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AuroraColors.fg2),
                  ),
                  const Spacer(),
                  GestureDetector(
                    onTap: () => setState(() => _autoScroll = !_autoScroll),
                    child: Text(
                      _autoScroll ? '自动滚动: 开启' : '自动滚动: 关闭',
                      style: TextStyle(fontSize: 11, color: _autoScroll ? AuroraColors.accent : AuroraColors.fg4),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),

              Container(
                height: 260,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFF0D1117),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AuroraColors.border),
                ),
                child: status.recentLogs.isEmpty
                  ? const Center(child: Text('等待采集器日志输出...', style: TextStyle(color: AuroraColors.fg4, fontSize: 12)))
                  : ListView.builder(
                      controller: _logScrollController,
                      itemCount: status.recentLogs.length,
                      itemBuilder: (context, idx) {
                        final line = status.recentLogs[idx];
                        Color color = const Color(0xFF9CA3AF);
                        if (line.contains('ONLINE') || line.contains('Connected')) {
                          color = const Color(0xFF34D399);
                        } else if (line.contains('Error') || line.contains('failed')) {
                          color = const Color(0xFFF87171);
                        } else if (line.contains('Watching') || line.contains('Discovered')) {
                          color = const Color(0xFF60A5FA);
                        }
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 2),
                          child: Text(
                            line,
                            style: TextStyle(
                              fontFamily: 'Courier',
                              fontSize: 11.5,
                              color: color,
                            ),
                          ),
                        );
                      },
                    ),
              ),
            ],
          ),
        );
      },
    );
  }
}
