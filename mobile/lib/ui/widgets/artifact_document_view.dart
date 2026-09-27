import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../core/theme/aurora_theme.dart';
import '../../models/agent_artifact.dart';
import 'app_markdown.dart';

/// Read at most this much of a document; agents rarely write more, and a huge
/// log shouldn't stall the workspace.
const artifactTextLimit = 2 * 1024 * 1024;

/// Formats the workspace can't show as text; they open in another app.
const _binaryExtensions = {'pdf', 'xlsx', 'xls', 'parquet', 'docx', 'doc', 'pptx', 'ppt', 'zip'};

bool artifactIsText(AgentArtifact a) {
  final ext = p.extension(a.rawPath.split('?').first).replaceFirst('.', '').toLowerCase();
  return !_binaryExtensions.contains(ext);
}

/// Only these platforms have a system web view the plugin can embed.
bool get htmlPreviewSupported => Platform.isMacOS || Platform.isIOS || Platform.isAndroid;

/// Text of an artifact, read from disk when it's on this machine, otherwise
/// streamed from the device that has it (only the first [artifactTextLimit] bytes).
Future<({String text, bool truncated})> loadArtifactText(AgentArtifact a, String streamUrl) async {
  final local = File(a.rawPath.replaceFirst(RegExp(r'^file://'), ''));
  List<int> bytes;
  var truncated = false;
  if (!a.rawPath.startsWith('http') && local.existsSync()) {
    truncated = local.lengthSync() > artifactTextLimit;
    bytes = await local.openRead(0, artifactTextLimit).fold<List<int>>(<int>[], (all, chunk) => all..addAll(chunk));
  } else {
    final resp = await Dio().get<List<int>>(
      streamUrl,
      options: Options(
        responseType: ResponseType.bytes,
        headers: {'Range': 'bytes=0-${artifactTextLimit - 1}'},
        receiveTimeout: const Duration(seconds: 60),
      ),
    );
    bytes = resp.data ?? const [];
    final total = RegExp(r'/(\d+)$').firstMatch(resp.headers.value('content-range') ?? '')?.group(1);
    truncated = (total != null && int.parse(total) > artifactTextLimit) || bytes.length > artifactTextLimit;
    if (bytes.length > artifactTextLimit) bytes = bytes.sublist(0, artifactTextLimit);
  }
  return (text: utf8.decode(bytes, allowMalformed: true), truncated: truncated);
}

/// Shows an HTML, Markdown or text artifact inside the workspace.
class ArtifactDocumentView extends StatefulWidget {
  final AgentArtifact artifact;
  final String streamUrl;
  final VoidCallback onOpenExternal;

  const ArtifactDocumentView({
    super.key,
    required this.artifact,
    required this.streamUrl,
    required this.onOpenExternal,
  });

  @override
  State<ArtifactDocumentView> createState() => _ArtifactDocumentViewState();
}

class _ArtifactDocumentViewState extends State<ArtifactDocumentView> {
  String? _text;
  bool _truncated = false;
  String? _error;
  bool _showSource = false;

  AgentArtifact get _a => widget.artifact;
  bool get _isHtml => _a.type == ArtifactType.html;
  bool get _isMarkdown => _a.type == ArtifactType.markdown;

  @override
  void initState() {
    super.initState();
    if (artifactIsText(_a)) _load();
  }

  Future<void> _load() async {
    setState(() {
      _error = null;
      _text = null;
    });
    try {
      final r = await loadArtifactText(_a, widget.streamUrl);
      if (!mounted) return;
      setState(() {
        _text = r.text;
        _truncated = r.truncated;
      });
    } catch (e) {
      if (!mounted) return;
      final code = e is DioException ? e.response?.statusCode : null;
      setState(() => _error = switch (code) {
            404 => '找不到这个文件：设备不在线，或文件已被移走。',
            403 => '没有权限读取这台设备上的文件。',
            _ => '读取失败：${e is DioException ? (e.message ?? e.type.name) : e}',
          });
    }
  }

  void _copy() {
    if (_text == null) return;
    Clipboard.setData(ClipboardData(text: _text!));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('已复制内容'), duration: Duration(seconds: 2), behavior: SnackBarBehavior.floating),
    );
  }

  @override
  Widget build(BuildContext context) {
    final canRender = (_isHtml && htmlPreviewSupported) || _isMarkdown;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.fromLTRB(14, 8, 8, 8),
          decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: AuroraColors.border))),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(_a.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: AuroraColors.fg1)),
                    Text(_a.rawPath,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 11,
                          color: AuroraColors.fg3,
                          fontFamily: 'monospace',
                          fontFamilyFallback: AuroraTheme.monospaceFontFamilyFallback,
                        )),
                  ],
                ),
              ),
              if (canRender && _text != null)
                _toolButton(
                  _showSource ? Icons.visibility_outlined : Icons.code_rounded,
                  _showSource ? '渲染' : '源码',
                  () => setState(() => _showSource = !_showSource),
                ),
              if (_text != null) _toolButton(Icons.copy_rounded, '复制', _copy),
              _toolButton(Icons.open_in_new_rounded, _isHtml ? '浏览器' : '外部打开', widget.onOpenExternal),
            ],
          ),
        ),
        if (_truncated)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            color: AuroraColors.warn.withValues(alpha: 0.07),
            child: const Text('文件较大，只显示了前 2 MB。',
                style: TextStyle(fontSize: 12, color: AuroraColors.warnText)),
          ),
        Expanded(child: _body()),
      ],
    );
  }

  Widget _toolButton(IconData icon, String label, VoidCallback onTap) => TextButton.icon(
        onPressed: onTap,
        style: TextButton.styleFrom(
          foregroundColor: AuroraColors.fg2,
          minimumSize: const Size(0, 32),
          padding: const EdgeInsets.symmetric(horizontal: 8),
        ),
        icon: Icon(icon, size: 15),
        label: Text(label, style: const TextStyle(fontSize: 12.5)),
      );

  Widget _body() {
    if (!artifactIsText(_a)) {
      return _placeholder(Icons.description_outlined, '这种格式没法在工作台里直接显示', '用系统里对应的应用打开。',
          action: ('外部打开', widget.onOpenExternal));
    }
    if (_error != null) {
      return _placeholder(Icons.error_outline_rounded, _error!, null, action: ('重试', _load));
    }
    final text = _text;
    if (text == null) return const Center(child: CircularProgressIndicator(strokeWidth: 2));

    if (_isHtml && !_showSource) {
      if (htmlPreviewSupported) return ArtifactHtmlView(key: ValueKey(_a.rawPath), artifact: _a, html: text);
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            color: AuroraColors.chip,
            child: Row(
              children: [
                const Expanded(
                  child: Text('这个平台暂不支持内嵌网页，下面是源码。',
                      style: TextStyle(fontSize: 12.5, color: AuroraColors.fg2)),
                ),
                TextButton(onPressed: widget.onOpenExternal, child: const Text('在浏览器打开')),
              ],
            ),
          ),
          Expanded(child: _source(text)),
        ],
      );
    }
    if (_isMarkdown && !_showSource) {
      return SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
        child: AppMarkdown(
          data: text,
          baseTextStyle: const TextStyle(fontSize: 14, height: 1.65, color: AuroraColors.fgBody),
        ),
      );
    }
    return _source(text);
  }

  Widget _source(String text) => Container(
        color: AuroraColors.terminal,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
          child: SelectableText(
            text,
            style: const TextStyle(
              fontSize: 12.5,
              height: 1.6,
              color: AuroraColors.fgCode,
              fontFamily: 'monospace',
              fontFamilyFallback: AuroraTheme.monospaceFontFamilyFallback,
            ),
          ),
        ),
      );

  Widget _placeholder(IconData icon, String title, String? body, {(String, VoidCallback)? action}) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 36, color: AuroraColors.fg3),
              const SizedBox(height: 12),
              Text(title, textAlign: TextAlign.center, style: const TextStyle(fontSize: 14, color: AuroraColors.fg1)),
              if (body != null) ...[
                const SizedBox(height: 4),
                Text(body, textAlign: TextAlign.center, style: const TextStyle(fontSize: 12.5, color: AuroraColors.fg3)),
              ],
              if (action != null) ...[
                const SizedBox(height: 14),
                OutlinedButton(onPressed: action.$2, child: Text(action.$1)),
              ],
            ],
          ),
        ),
      );
}

/// An HTML artifact in a system web view. A file on this machine loads from
/// disk so its relative css/js/images resolve; one on another device loads
/// from the text already fetched. Links that leave the page open in the browser.
class ArtifactHtmlView extends StatefulWidget {
  final AgentArtifact artifact;
  final String html;

  const ArtifactHtmlView({super.key, required this.artifact, required this.html});

  @override
  State<ArtifactHtmlView> createState() => _ArtifactHtmlViewState();
}

class _ArtifactHtmlViewState extends State<ArtifactHtmlView> {
  late final WebViewController _controller;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    final local = File(widget.artifact.rawPath.replaceFirst(RegExp(r'^file://'), ''));
    final isLocal = !widget.artifact.rawPath.startsWith('http') && local.existsSync();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(NavigationDelegate(
        onPageFinished: (_) {
          if (mounted) setState(() => _loaded = true);
        },
        onNavigationRequest: (request) {
          final uri = Uri.tryParse(request.url);
          final leavesPage = request.isMainFrame &&
              uri != null &&
              (uri.scheme == 'http' || uri.scheme == 'https' || uri.scheme == 'mailto');
          if (leavesPage) {
            launchUrl(uri, mode: LaunchMode.externalApplication);
            return NavigationDecision.prevent;
          }
          return NavigationDecision.navigate;
        },
      ));
    if (isLocal) {
      _controller.loadFile(local.path);
    } else {
      _controller.loadHtmlString(widget.html);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(child: WebViewWidget(controller: _controller)),
        if (!_loaded) const Center(child: CircularProgressIndicator(strokeWidth: 2)),
      ],
    );
  }
}
