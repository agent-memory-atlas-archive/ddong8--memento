import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/storage.dart';
import '../../core/theme/aurora_theme.dart';
import '../../models/agent_artifact.dart';
import 'embedded_video_player.dart';

class ArtifactCard extends StatefulWidget {
  final AgentArtifact artifact;
  final VoidCallback? onOpenWorkspace;

  const ArtifactCard({
    super.key,
    required this.artifact,
    this.onOpenWorkspace,
  });

  @override
  State<ArtifactCard> createState() => _ArtifactCardState();
}

class _ArtifactCardState extends State<ArtifactCard> {
  String? _serverUrl;
  String? _token;
  bool _copied = false;

  @override
  void initState() {
    super.initState();
    _loadServerUrl();
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

  Future<void> _handlePlayOrOpen() async {
    final streamUrl = widget.artifact.getStreamUrl(_serverUrl ?? 'https://mem.ihasy.com', token: _token);
    
    // 1. If desktop wide screen workspace callback provided, open directly in side canvas
    if (widget.onOpenWorkspace != null) {
      widget.onOpenWorkspace!();
      return;
    }

    // 2. If video artifact, open embedded dialog directly inside the app (never jump to browser!)
    if (widget.artifact.type == ArtifactType.video) {
      showDialog(
        context: context,
        builder: (ctx) => Dialog(
          backgroundColor: Colors.black,
          insetPadding: const EdgeInsets.all(16),
          child: Container(
            constraints: const BoxConstraints(maxWidth: 900, maxHeight: 560),
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AuroraColors.borderStrong),
            ),
            child: Stack(
              children: [
                EmbeddedVideoPlayer(
                  streamUrl: streamUrl,
                  title: widget.artifact.title,
                ),
                Positioned(
                  top: 10,
                  right: 10,
                  child: IconButton(
                    icon: const Icon(Icons.close, color: Colors.white70),
                    onPressed: () => Navigator.of(ctx).pop(),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      return;
    }

    // 3. Fallback for document or external URL
    final uri = Uri.parse(streamUrl);
    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    } catch (_) {}
  }

  void _copyPath() {
    Clipboard.setData(ClipboardData(text: widget.artifact.rawPath));
    setState(() => _copied = true);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('已复制产物物理路径'),
        duration: Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ),
    );
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) setState(() => _copied = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final a = widget.artifact;
    final isVideo = a.type == ArtifactType.video;
    final isAudio = a.type == ArtifactType.audio;
    final isImage = a.type == ArtifactType.image;
    final isHtml = a.type == ArtifactType.html;

    Color badgeColor;
    switch (a.type) {
      case ArtifactType.video:
        badgeColor = const Color(0xFF38BDF8); // sky
        break;
      case ArtifactType.audio:
        badgeColor = const Color(0xFF34D399); // emerald
        break;
      case ArtifactType.image:
        badgeColor = const Color(0xFFF472B6); // pink
        break;
      case ArtifactType.html:
        badgeColor = const Color(0xFFFBBF24); // amber
        break;
      default:
        badgeColor = AuroraColors.accent;
    }

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: badgeColor.withOpacity(0.35), width: 1.2),
        boxShadow: [
          BoxShadow(
            color: badgeColor.withOpacity(0.08),
            blurRadius: 14,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // 1. Top Header Bar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            color: const Color(0xFF1E293B).withOpacity(0.7),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: badgeColor.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: badgeColor.withOpacity(0.6), width: 0.8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(a.type.iconEmoji, style: const TextStyle(fontSize: 11)),
                      const SizedBox(width: 4),
                      Text(
                        a.type.label,
                        style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w600,
                          color: badgeColor,
                        ),
                      ),
                    ],
                  ),
                ),
                if (a.sizeLabel != null && a.sizeLabel!.isNotEmpty) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: AuroraColors.chip,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: AuroraColors.border, width: 0.8),
                    ),
                    child: Text(
                      a.sizeLabel!,
                      style: const TextStyle(fontSize: 10, color: AuroraColors.fg3),
                    ),
                  ),
                ],
                const Spacer(),
                // Copy path icon
                InkWell(
                  onTap: _copyPath,
                  borderRadius: BorderRadius.circular(6),
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: Icon(
                      _copied ? Icons.check : Icons.copy_rounded,
                      size: 14,
                      color: _copied ? AuroraColors.success : AuroraColors.fg3,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // 2. Main Content Canvas
          InkWell(
            onTap: _handlePlayOrOpen,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [Color(0xFF0F172A), Color(0xFF131D33)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      // Media Play/View Graphic
                      Container(
                        width: isVideo ? 54 : 44,
                        height: isVideo ? 54 : 44,
                        decoration: BoxDecoration(
                          color: badgeColor.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(isVideo ? 12 : 10),
                          border: Border.all(color: badgeColor.withOpacity(0.5)),
                        ),
                        child: Icon(
                          isVideo
                              ? Icons.play_arrow_rounded
                              : (isAudio
                                  ? Icons.audiotrack_rounded
                                  : (isImage
                                      ? Icons.image_rounded
                                      : (isHtml ? Icons.web_rounded : Icons.insert_drive_file_rounded))),
                          size: isVideo ? 34 : 24,
                          color: badgeColor,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              a.title,
                              style: const TextStyle(
                                fontSize: 13.5,
                                fontWeight: FontWeight.w600,
                                color: AuroraColors.fg1,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              a.rawPath,
                              style: const TextStyle(
                                fontSize: 11,
                                color: AuroraColors.fg3,
                                fontFamily: 'monospace',
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  // Action Buttons Row
                  Row(
                    children: [
                      ElevatedButton.icon(
                        onPressed: _handlePlayOrOpen,
                        icon: Icon(
                          isVideo ? Icons.play_circle_fill_rounded : Icons.open_in_browser_rounded,
                          size: 16,
                          color: Colors.white,
                        ),
                        label: Text(
                          isVideo ? '立即播放预览' : (isHtml ? '在工作台渲染' : '点击查看'),
                          style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: badgeColor.withOpacity(0.85),
                          foregroundColor: Colors.white,
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                      ),
                      const SizedBox(width: 8),
                      if (widget.onOpenWorkspace != null)
                        OutlinedButton.icon(
                          onPressed: widget.onOpenWorkspace,
                          icon: const Icon(Icons.splitscreen_rounded, size: 14, color: AuroraColors.fg2),
                          label: const Text('分屏工作区', style: TextStyle(fontSize: 11.5, color: AuroraColors.fg2)),
                          style: OutlinedButton.styleFrom(
                            side: const BorderSide(color: AuroraColors.borderStrong),
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
