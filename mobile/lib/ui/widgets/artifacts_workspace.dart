import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/storage.dart';
import '../../core/theme/aurora_theme.dart';
import '../../models/agent_artifact.dart';
import 'app_markdown.dart';

class ArtifactsWorkspace extends StatefulWidget {
  final List<AgentArtifact> artifacts;
  final AgentArtifact? initialSelected;
  final VoidCallback? onClose;

  const ArtifactsWorkspace({
    super.key,
    required this.artifacts,
    this.initialSelected,
    this.onClose,
  });

  @override
  State<ArtifactsWorkspace> createState() => _ArtifactsWorkspaceState();
}

class _ArtifactsWorkspaceState extends State<ArtifactsWorkspace> {
  late AgentArtifact _selectedArtifact;
  String? _serverUrl;
  String? _token;

  @override
  void initState() {
    super.initState();
    _selectedArtifact = widget.initialSelected ??
        (widget.artifacts.isNotEmpty
            ? widget.artifacts.first
            : AgentArtifact(
                id: 'empty',
                title: '产物工作台',
                type: ArtifactType.document,
                rawPath: '',
              ));
    _loadServerUrl();
  }

  @override
  void didUpdateWidget(covariant ArtifactsWorkspace oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialSelected != null && widget.initialSelected != _selectedArtifact) {
      _selectedArtifact = widget.initialSelected!;
    }
  }

  Future<void> _loadServerUrl() async {
    final url = await AppStorage.getServerUrl();
    final token = await AppStorage.getToken();
    if (mounted) {
      setState(() {
        _serverUrl = url;
        _token = token;
      });
    }
  }

  Future<void> _handleLaunchExternal() async {
    final streamUrl = _selectedArtifact.getStreamUrl(_serverUrl ?? 'https://mem.ihasy.com', token: _token);
    final uri = Uri.parse(streamUrl);
    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    } catch (_) {}
  }

  void _copyPhysicalPath() {
    Clipboard.setData(ClipboardData(text: _selectedArtifact.rawPath));
    _showFeedback('已复制物理路径');
  }

  void _copyStreamUrl() {
    final streamUrl = _selectedArtifact.getStreamUrl(_serverUrl ?? 'https://mem.ihasy.com', token: _token);
    Clipboard.setData(ClipboardData(text: streamUrl));
    _showFeedback('已复制媒体流 URL');
  }

  void _showFeedback(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final a = _selectedArtifact;
    final streamUrl = a.getStreamUrl(_serverUrl ?? 'https://mem.ihasy.com', token: _token);

    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF090D16),
        border: Border(left: BorderSide(color: AuroraColors.borderStrong, width: 1.2)),
      ),
      child: Column(
        children: [
          // 1. Top Tabs & Controls Bar
          Container(
            height: 44,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: const BoxDecoration(
              color: Color(0xFF0F172A),
              border: Border(bottom: BorderSide(color: AuroraColors.borderStrong)),
            ),
            child: Row(
              children: [
                // Workspace Label
                const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.dashboard_customize_rounded, size: 15, color: AuroraColors.accent),
                    SizedBox(width: 6),
                    Text(
                      'Artifacts 工作台',
                      style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: AuroraColors.fg1),
                    ),
                  ],
                ),
                const SizedBox(width: 14),

                // Artifact Tabs
                Expanded(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: widget.artifacts.map((art) {
                        final isSelected = art.rawPath == a.rawPath;
                        return Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: InkWell(
                            onTap: () => setState(() {
                              _selectedArtifact = art;
                            }),
                            borderRadius: BorderRadius.circular(6),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: isSelected ? AuroraColors.accentSoft : AuroraColors.chip,
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(
                                  color: isSelected ? AuroraColors.accent : AuroraColors.border,
                                  width: 1,
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(art.type.iconEmoji, style: const TextStyle(fontSize: 11)),
                                  const SizedBox(width: 4),
                                  ConstrainedBox(
                                    constraints: const BoxConstraints(maxWidth: 120),
                                    child: Text(
                                      art.title,
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: isSelected ? AuroraColors.accent : AuroraColors.fg2,
                                        fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ),

                // Right Toolbar Action Icons
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.open_in_new_rounded, size: 16, color: AuroraColors.fg2),
                      tooltip: '外接播放/新窗口打开',
                      onPressed: _handleLaunchExternal,
                    ),
                    IconButton(
                      icon: const Icon(Icons.link_rounded, size: 16, color: AuroraColors.fg2),
                      tooltip: '复制流媒体 URL (Range 直链)',
                      onPressed: _copyStreamUrl,
                    ),
                    IconButton(
                      icon: const Icon(Icons.folder_copy_outlined, size: 16, color: AuroraColors.fg2),
                      tooltip: '复制物理路径',
                      onPressed: _copyPhysicalPath,
                    ),
                    if (widget.onClose != null)
                      IconButton(
                        icon: const Icon(Icons.close_rounded, size: 17, color: AuroraColors.fg3),
                        tooltip: '收起工作台',
                        onPressed: widget.onClose,
                      ),
                  ],
                ),
              ],
            ),
          ),

          // 2. Main Content Canvas
          Expanded(
            child: a.rawPath.isEmpty
                ? const Center(
                    child: Text('当前对话暂无生成的产物文件', style: TextStyle(color: AuroraColors.fg3)),
                  )
                : _buildArtifactCanvas(a, streamUrl),
          ),

          // 3. Bottom Status & Path Meta Bar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: const BoxDecoration(
              color: Color(0xFF0F172A),
              border: Border(top: BorderSide(color: AuroraColors.borderStrong)),
            ),
            child: Row(
              children: [
                Container(
                  width: 7,
                  height: 7,
                  decoration: const BoxDecoration(
                    color: Color(0xFF10B981),
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  a.deviceId != null ? '设备: ${a.deviceId}' : '跨设备媒体流已就绪',
                  style: const TextStyle(fontSize: 10.5, color: AuroraColors.fg3),
                ),
                const Spacer(),
                Text(
                  a.sizeLabel != null ? '体积: ${a.sizeLabel}' : '',
                  style: const TextStyle(fontSize: 10.5, color: AuroraColors.fg3),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildArtifactCanvas(AgentArtifact a, String streamUrl) {
    switch (a.type) {
      case ArtifactType.video:
        return _buildVideoCanvas(a, streamUrl);
      case ArtifactType.audio:
        return _buildAudioCanvas(a, streamUrl);
      case ArtifactType.image:
        return _buildImageCanvas(a, streamUrl);
      case ArtifactType.html:
        return _buildHtmlCanvas(a, streamUrl);
      case ArtifactType.markdown:
      case ArtifactType.document:
      case ArtifactType.code:
        return _buildDocCanvas(a, streamUrl);
    }
  }

  Widget _buildVideoCanvas(AgentArtifact a, String streamUrl) {
    return Center(
      child: Container(
        margin: const EdgeInsets.all(24),
        constraints: const BoxConstraints(maxWidth: 720, maxHeight: 460),
        decoration: BoxDecoration(
          color: Colors.black,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFF38BDF8).withOpacity(0.4), width: 1.5),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF38BDF8).withOpacity(0.12),
              blurRadius: 30,
              spreadRadius: 2,
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          alignment: Alignment.center,
          children: [
            // Dark Media Cinema Stage
            Container(
              color: const Color(0xFF030712),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 80,
                      height: 80,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFF0284C7), Color(0xFF38BDF8)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF38BDF8).withOpacity(0.4),
                            blurRadius: 24,
                            spreadRadius: 2,
                          ),
                        ],
                      ),
                      child: IconButton(
                        icon: const Icon(Icons.play_arrow_rounded, size: 48, color: Colors.white),
                        onPressed: _handleLaunchExternal,
                      ),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      a.title,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '已建立 HTTP 206 分段媒体流 · 支持任意拖动快进快退',
                      style: TextStyle(fontSize: 11.5, color: Colors.white.withOpacity(0.6)),
                    ),
                    const SizedBox(height: 18),
                    ElevatedButton.icon(
                      onPressed: _handleLaunchExternal,
                      icon: const Icon(Icons.movie_filter_rounded, size: 16),
                      label: const Text('立即全屏沉浸播放 (本地硬解秒开)'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF0284C7),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAudioCanvas(AgentArtifact a, String streamUrl) {
    return Center(
      child: Container(
        margin: const EdgeInsets.all(24),
        padding: const EdgeInsets.all(28),
        constraints: const BoxConstraints(maxWidth: 520),
        decoration: BoxDecoration(
          color: const Color(0xFF0F172A),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFF34D399).withOpacity(0.4)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.graphic_eq_rounded, size: 48, color: Color(0xFF34D399)),
            const SizedBox(height: 14),
            Text(
              a.title,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AuroraColors.fg1),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: _handleLaunchExternal,
              icon: const Icon(Icons.play_arrow_rounded, size: 18),
              label: const Text('播放音频产物'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF059669),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildImageCanvas(AgentArtifact a, String streamUrl) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.network(
                streamUrl,
                fit: BoxFit.contain,
                errorBuilder: (_, __, ___) => Container(
                  padding: const EdgeInsets.all(24),
                  color: const Color(0xFF0F172A),
                  child: Column(
                    children: [
                      const Icon(Icons.broken_image_rounded, size: 36, color: AuroraColors.fg3),
                      const SizedBox(height: 8),
                      Text('无法直接加载图片: ${a.rawPath}', style: const TextStyle(color: AuroraColors.fg3)),
                      const SizedBox(height: 12),
                      ElevatedButton(onPressed: _handleLaunchExternal, child: const Text('在新标签打开')),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text(a.title, style: const TextStyle(fontSize: 13, color: AuroraColors.fg2)),
          ],
        ),
      ),
    );
  }

  Widget _buildHtmlCanvas(AgentArtifact a, String streamUrl) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          color: const Color(0xFF0F172A),
          child: Row(
            children: [
              const Icon(Icons.language_rounded, size: 14, color: Color(0xFFFBBF24)),
              const SizedBox(width: 6),
              const Text('交互式 HTML 沙箱画布', style: TextStyle(fontSize: 11, color: Color(0xFFFBBF24), fontWeight: FontWeight.w600)),
              const Spacer(),
              ElevatedButton.icon(
                onPressed: _handleLaunchExternal,
                icon: const Icon(Icons.launch_rounded, size: 13),
                label: const Text('全屏交互预览', style: TextStyle(fontSize: 11)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFD97706),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  minimumSize: const Size(60, 26),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.html_rounded, size: 64, color: Color(0xFFFBBF24)),
                const SizedBox(height: 14),
                Text(a.title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: AuroraColors.fg1)),
                const SizedBox(height: 6),
                Text(a.rawPath, style: const TextStyle(fontSize: 11, color: AuroraColors.fg3, fontFamily: 'monospace')),
                const SizedBox(height: 18),
                ElevatedButton.icon(
                  onPressed: _handleLaunchExternal,
                  icon: const Icon(Icons.play_circle_outline_rounded, size: 16),
                  label: const Text('启动交互原型'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFD97706),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDocCanvas(AgentArtifact a, String streamUrl) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(a.type.iconEmoji, style: const TextStyle(fontSize: 18)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  a.title,
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AuroraColors.fg1),
                ),
              ),
              OutlinedButton.icon(
                onPressed: _handleLaunchExternal,
                icon: const Icon(Icons.open_in_browser, size: 14),
                label: const Text('外部查看', style: TextStyle(fontSize: 11)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(a.rawPath, style: const TextStyle(fontSize: 11, color: AuroraColors.fg3, fontFamily: 'monospace')),
          const Divider(height: 24, color: AuroraColors.borderStrong),
          AppMarkdown(data: '### 文档产物摘要\n- **物理路径**: `${a.rawPath}`\n- **类型**: ${a.type.label}\n\n已成功生成并挂载至 Memento Artifacts 资源树。'),
        ],
      ),
    );
  }
}
