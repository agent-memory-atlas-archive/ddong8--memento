import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import '../../core/services/update_service.dart';
import '../../core/theme/aurora_theme.dart';

class UpdateDialog extends StatefulWidget {
  final UpdateInfo info;

  const UpdateDialog({super.key, required this.info});

  static Future<void> show(BuildContext context, UpdateInfo info) {
    return showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => UpdateDialog(info: info),
    );
  }

  @override
  State<UpdateDialog> createState() => _UpdateDialogState();
}

class _UpdateDialogState extends State<UpdateDialog> {
  bool _isDownloading = false;
  double _progress = 0.0;
  String _statusText = '';
  String _currentSource = '';
  String? _downloadedPath;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _checkCachedPackage();
  }

  Future<void> _checkCachedPackage() async {
    try {
      final cached = await UpdateService.checkCachedPackage(widget.info);
      if (cached != null && mounted) {
        setState(() {
          _downloadedPath = cached;
          _progress = 1.0;
          _statusText = '更新包已在后台下载就绪，可直接重启更新';
        });
      }
    } catch (_) {}
  }

  String _formatSize(int? bytes) {
    if (bytes == null || bytes <= 0) return '';
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    }
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  void _startDownload() {
    setState(() {
      _isDownloading = true;
      _errorMessage = null;
      _statusText = '准备下载...';
      _currentSource = '';
      _progress = 0.0;
    });

    final targetUrl = widget.info.downloadUrl ?? widget.info.htmlUrl;

    UpdateService.downloadAndInstall(
      downloadUrl: targetUrl,
      upstreamUrl: widget.info.upstreamUrl,
      version: widget.info.version,
      fileName: widget.info.assetName,
      onSourceChanged: (sourceLabel) {
        if (!mounted) return;
        setState(() {
          _currentSource = sourceLabel;
          _statusText = '[$sourceLabel] 连接中...';
        });
      },
      onProgress: (received, total) {
        if (!mounted) return;
        setState(() {
          final prefix = _currentSource.isNotEmpty ? '[$_currentSource] ' : '';
          if (total > 0) {
            _progress = received / total;
            final recMb = (received / (1024 * 1024)).toStringAsFixed(1);
            final totMb = (total / (1024 * 1024)).toStringAsFixed(1);
            _statusText = '$prefix下载中: $recMb / $totMb MB (${(_progress * 100).toInt()}%)';
          } else {
            final recMb = (received / (1024 * 1024)).toStringAsFixed(1);
            _statusText = '$prefix已下载: $recMb MB';
          }
        });
      },
      onError: (err) {
        if (!mounted) return;
        setState(() {
          _isDownloading = false;
          _errorMessage = err;
        });
      },
      onComplete: (savePath) {
        if (!mounted) return;
        setState(() {
          _isDownloading = false;
          _downloadedPath = savePath;
          _statusText = '下载完成，正在自动热更新并重启...';
        });
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final info = widget.info;
    final sizeText = _formatSize(info.assetSize);

    return Dialog(
      backgroundColor: AuroraColors.surfaceSolid,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: const BorderSide(color: AuroraColors.borderStrong),
      ),
      child: Container(
        width: 480,
        constraints: const BoxConstraints(maxHeight: 560),
        padding: const EdgeInsets.all(22),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: AuroraColors.accent.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.system_update_alt_rounded,
                    color: AuroraColors.accent,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Text(
                            '发现新版本',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: AuroraColors.fg1,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: AuroraColors.accent,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              'v${info.version}',
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                          ),
                          if (info.isFromCustomServer) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                              decoration: BoxDecoration(
                                color: AuroraColors.success.withOpacity(0.2),
                                borderRadius: BorderRadius.circular(4),
                                border: Border.all(color: AuroraColors.success.withOpacity(0.4)),
                              ),
                              child: const Text(
                                '私有服务端',
                                style: TextStyle(
                                  fontSize: 10,
                                  color: AuroraColors.success,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 3),
                      Text(
                        '当前版本: v${info.currentVersion}${sizeText.isNotEmpty ? ' · 大小: $sizeText' : ''}',
                        style: const TextStyle(
                          fontSize: 12,
                          color: AuroraColors.fg3,
                        ),
                      ),
                    ],
                  ),
                ),
                if (!_isDownloading)
                  IconButton(
                    icon: const Icon(Icons.close, size: 20, color: AuroraColors.fg3),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            const Divider(height: 1, color: AuroraColors.border),
            const SizedBox(height: 14),

            // Release Notes Section
            const Text(
              '更新内容:',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AuroraColors.fg2,
              ),
            ),
            const SizedBox(height: 8),
            Flexible(
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AuroraColors.chip,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AuroraColors.border),
                ),
                child: SingleChildScrollView(
                  child: MarkdownBody(
                    data: info.releaseNotes,
                    styleSheet: MarkdownStyleSheet(
                      p: const TextStyle(fontSize: 12.5, color: AuroraColors.fg2, height: 1.5),
                      code: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 11.5,
                        backgroundColor: Colors.transparent,
                        color: AuroraColors.accent,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Progress or Error indicator
            if (_isDownloading) ...[
              LinearProgressIndicator(
                value: _progress > 0 ? _progress : null,
                backgroundColor: AuroraColors.chip,
                color: AuroraColors.accent,
                borderRadius: BorderRadius.circular(4),
                minHeight: 6,
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    _statusText,
                    style: const TextStyle(fontSize: 12, color: AuroraColors.accent),
                  ),
                  Text(
                    '${(_progress * 100).toInt()}%',
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AuroraColors.accent),
                  ),
                ],
              ),
              const SizedBox(height: 12),
            ] else if (_errorMessage != null) ...[
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: AuroraColors.danger.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  _errorMessage!,
                  style: const TextStyle(fontSize: 12, color: AuroraColors.danger),
                ),
              ),
              const SizedBox(height: 12),
            ] else if (_downloadedPath != null) ...[
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: AuroraColors.success.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  _statusText,
                  style: const TextStyle(fontSize: 12, color: AuroraColors.success),
                ),
              ),
              const SizedBox(height: 12),
            ],

            // Actions
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton.icon(
                  icon: const Icon(Icons.copy_rounded, size: 15),
                  label: const Text('复制直链'),
                  style: TextButton.styleFrom(
                    foregroundColor: AuroraColors.fg3,
                  ),
                  onPressed: () {
                    final bestUrl = info.upstreamUrl ?? info.downloadUrl ?? info.htmlUrl;
                    Clipboard.setData(ClipboardData(text: bestUrl));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('安装包直链已复制到剪贴板，可在浏览器或下载器中下载'),
                        duration: Duration(seconds: 3),
                      ),
                    );
                  },
                ),
                const SizedBox(width: 4),
                TextButton.icon(
                  icon: const Icon(Icons.open_in_browser, size: 16),
                  label: const Text('网页下载'),
                  style: TextButton.styleFrom(
                    foregroundColor: AuroraColors.fg3,
                  ),
                  onPressed: () => UpdateService.openReleasePage(info.htmlUrl),
                ),
                const SizedBox(width: 8),
                if (!_isDownloading && _downloadedPath == null) ...[
                  OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AuroraColors.fg2,
                      side: const BorderSide(color: AuroraColors.border),
                    ),
                    child: const Text('稍后再说'),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton.icon(
                    icon: const Icon(Icons.download_rounded, size: 16),
                    label: const Text('立即更新'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AuroraColors.accent,
                      foregroundColor: Colors.white,
                      elevation: 0,
                    ),
                    onPressed: _startDownload,
                  ),
                ] else if (_downloadedPath != null) ...[
                  ElevatedButton.icon(
                    icon: const Icon(Icons.bolt_rounded, size: 16),
                    label: const Text('立即重启更新'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AuroraColors.accent,
                      foregroundColor: Colors.white,
                      elevation: 0,
                    ),
                    onPressed: () => UpdateService.installPackage(_downloadedPath!),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}