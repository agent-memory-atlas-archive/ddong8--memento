import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import '../../core/services/media_cache_manager.dart';

class EmbeddedVideoPlayer extends StatefulWidget {
  final String streamUrl;
  final String? p2pUrl;
  final String? cacheKey;
  final String? title;
  final VoidCallback? onLaunchExternal;
  final bool autoCache;

  const EmbeddedVideoPlayer({
    super.key,
    required this.streamUrl,
    this.p2pUrl,
    this.cacheKey,
    this.title,
    this.onLaunchExternal,
    this.autoCache = true,
  });

  @override
  State<EmbeddedVideoPlayer> createState() => _EmbeddedVideoPlayerState();
}

class _EmbeddedVideoPlayerState extends State<EmbeddedVideoPlayer> {
  late final Player _player;
  late final VideoController _controller;

  bool _isPlaying = false;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  bool _isBuffering = true;
  String? _errorMessage;
  bool _showControls = true;
  Timer? _hideControlsTimer;

  bool _isP2pActive = false;
  bool _isLocalCached = false;
  bool _isCaching = false;
  double _cacheProgress = 0.0;
  String? _activeUrl;
  StreamSubscription<MediaCacheProgress>? _cacheSubscription;

  @override
  void initState() {
    super.initState();
    _initCacheState();
    _initPlayer();
  }

  void _initCacheState() {
    _cacheSubscription?.cancel();
    _cacheSubscription = null;

    final key = widget.cacheKey;
    if (key == null || key.isEmpty) return;

    final progress = MediaCacheManager.instance.getProgress(key);
    if (progress != null) {
      _cacheProgress = progress.progress;
      _isCaching = progress.isCaching;
      _isLocalCached = progress.isCompleted;
    } else if (MediaCacheManager.instance.isCached(key)) {
      _isLocalCached = true;
      _cacheProgress = 1.0;
      _isCaching = false;
    }

    _cacheSubscription = MediaCacheManager.instance.progressStream
        .where((p) => p.cacheKey == key)
        .listen((p) {
      if (mounted) {
        setState(() {
          _cacheProgress = p.progress;
          _isCaching = p.isCaching;
          if (p.isCompleted) {
            _isLocalCached = true;
          }
        });
      }
    });
  }

  void _initPlayer() {
    _player = Player();
    _controller = VideoController(_player);

    try {
      final p = _player.platform;
      (p as dynamic).setProperty('tls-verify', 'no');
    } catch (_) {}

    _player.stream.playing.listen((p) {
      if (mounted) setState(() => _isPlaying = p);
    });
    _player.stream.position.listen((pos) {
      if (mounted) setState(() => _position = pos);
    });
    _player.stream.duration.listen((dur) {
      if (mounted) setState(() => _duration = dur);
    });
    _player.stream.buffering.listen((b) {
      if (mounted) setState(() => _isBuffering = b);
    });
    _player.stream.error.listen((err) {
      if (mounted) setState(() => _errorMessage = err);
    });
    _player.stream.completed.listen((completed) {
      if (completed && widget.autoCache && !_isLocalCached && widget.cacheKey != null) {
        _triggerBackgroundCache(_activeUrl ?? widget.streamUrl);
      }
    });

    _resolveAndPlay();
  }

  Future<void> _resolveAndPlay() async {
    String targetUrl = widget.streamUrl;
    bool isP2p = false;
    bool isLocal = false;

    // 1. Check local file or existing local cache
    final key = widget.cacheKey;
    if (key != null && key.isNotEmpty) {
      try {
        final clean = key.replaceFirst(RegExp(r'^file://'), '');
        final directFile = File(clean);
        if (directFile.existsSync() && directFile.lengthSync() > 1024) {
          targetUrl = directFile.path;
          isLocal = true;
        }
      } catch (_) {}

      if (!isLocal) {
        final cached = await MediaCacheManager.instance.getCachedFile(key);
        if (cached != null && cached.existsSync()) {
          targetUrl = cached.path;
          isLocal = true;
        }
      }
    }

    // 2. Dual-mode Happy-Eyeballs probing:
    // If not local, and an IPv6 P2P direct URL is provided, probe reachability with 500ms timeout
    if (!isLocal && widget.p2pUrl != null && widget.p2pUrl!.isNotEmpty) {
      try {
        final client = HttpClient()..connectionTimeout = const Duration(milliseconds: 500);
        final uri = Uri.parse(widget.p2pUrl!);
        final req = await client.headUrl(uri).timeout(const Duration(milliseconds: 500));
        final resp = await req.close().timeout(const Duration(milliseconds: 500));
        if (resp.statusCode == HttpStatus.ok || resp.statusCode == HttpStatus.partialContent) {
          targetUrl = widget.p2pUrl!;
          isP2p = true;
          debugPrint('[EmbeddedVideoPlayer] Direct IPv6 P2P connectivity verified: $targetUrl');
        }
        client.close();
      } catch (e) {
        debugPrint('[EmbeddedVideoPlayer] IPv6 P2P probe failed or timed out ($e), falling back to relay: ${widget.streamUrl}');
      }
    }

    if (mounted) {
      setState(() {
        _isLocalCached = isLocal;
        _isP2pActive = isP2p;
        _activeUrl = targetUrl;
      });
    }

    _player.open(Media(targetUrl), play: true);
    _startHideTimer();

    // 3. Initiate background cache if not already cached and autoCache is true
    if (!isLocal && widget.autoCache && key != null && key.isNotEmpty) {
      _triggerBackgroundCache(targetUrl);
    }
  }

  void _triggerBackgroundCache(String downloadUrl) {
    final key = widget.cacheKey;
    if (key == null || key.isEmpty || _isLocalCached || _isCaching) return;

    setState(() => _isCaching = true);
    MediaCacheManager.instance.startCaching(
      downloadUrl,
      key,
      onProgress: (p) {
        if (mounted) {
          setState(() {
            _cacheProgress = p;
            _isCaching = true;
          });
        }
      },
      onCompleted: (file) {
        if (mounted) {
          setState(() {
            _isLocalCached = true;
            _isCaching = false;
            _cacheProgress = 1.0;
          });
        }
      },
    );
  }

  void _startHideTimer() {
    _hideControlsTimer?.cancel();
    _hideControlsTimer = Timer(const Duration(seconds: 3), () {
      if (mounted && _isPlaying) {
        setState(() => _showControls = false);
      }
    });
  }

  void _toggleControls() {
    setState(() => _showControls = !_showControls);
    if (_showControls) {
      _startHideTimer();
    }
  }

  @override
  void didUpdateWidget(covariant EmbeddedVideoPlayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.streamUrl != widget.streamUrl ||
        oldWidget.p2pUrl != widget.p2pUrl ||
        oldWidget.cacheKey != widget.cacheKey) {
      _errorMessage = null;
      _initCacheState();
      _resolveAndPlay();
    }
  }

  @override
  void dispose() {
    _cacheSubscription?.cancel();
    _hideControlsTimer?.cancel();
    _player.dispose();
    super.dispose();
  }

  String _formatDuration(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    final h = d.inHours;
    if (h > 0) {
      return '$h:$m:$s';
    }
    return '$m:$s';
  }

  String _diagnoseError(String err) {
    if (err.contains('Failed to open') || err.contains('404')) {
      return '未能读取到媒体文件：目标机器上的文件尚未生成、已被清理或路径不存在。\n请确认物理文件是否已生成完毕。';
    }
    if (err.contains('Failed to recognize file format')) {
      return '媒体流格式解析异常（通常因网络连接波动、TLS 证书校验或中继握手未就绪引起）。\n建议点击下方【重试加载】或【外接播放器】在外部播放器/浏览器中直接播放。';
    }
    if (err.contains('offline')) {
      return '目标采集设备当前处于离线状态，无法建立媒体流中继。\n请确认远端机器已开机并已连接网络。';
    }
    if (err.contains('401') || err.contains('403') || err.contains('token')) {
      return '访问凭证已过期或无权读取该设备文件，请重新登录后再试。';
    }
    return err;
  }

  @override
  Widget build(BuildContext context) {
    if (_errorMessage != null) {
      final friendlyTip = _diagnoseError(_errorMessage!);
      return Center(
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 24),
          padding: const EdgeInsets.all(22),
          constraints: const BoxConstraints(maxWidth: 580),
          decoration: BoxDecoration(
            color: const Color(0xFF1E1010),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.redAccent.withOpacity(0.35)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.videocam_off_rounded, color: Colors.redAccent, size: 40),
              const SizedBox(height: 12),
              Text(
                widget.title ?? '媒体文件加载失败',
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                friendlyTip,
                style: const TextStyle(color: Colors.white70, fontSize: 12.5, height: 1.45),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ElevatedButton.icon(
                    onPressed: () {
                      setState(() => _errorMessage = null);
                      _player.open(Media(widget.streamUrl), play: true);
                    },
                    icon: const Icon(Icons.refresh_rounded, size: 16),
                    label: const Text('重试加载'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF0284C7),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                  ),
                  if (widget.onLaunchExternal != null) ...[
                    const SizedBox(width: 12),
                    OutlinedButton.icon(
                      onPressed: widget.onLaunchExternal,
                      icon: const Icon(Icons.open_in_new_rounded, size: 15),
                      label: const Text('外接播放器'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white70,
                        side: BorderSide(color: Colors.white.withOpacity(0.2)),
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      );
    }

    return MouseRegion(
      onHover: (_) {
        if (!_showControls) {
          setState(() => _showControls = true);
        }
        _startHideTimer();
      },
      child: GestureDetector(
        onTap: _toggleControls,
        child: Container(
          color: Colors.black,
          child: Stack(
            alignment: Alignment.center,
            children: [
              // 1. Native Rendered Video Frame
              Video(
                controller: _controller,
                controls: NoVideoControls,
              ),

              // 2. Buffering Indicator
              if (_isBuffering)
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(30),
                  ),
                  child: const SizedBox(
                    width: 32,
                    height: 32,
                    child: CircularProgressIndicator(
                      strokeWidth: 3,
                      color: Color(0xFF38BDF8),
                    ),
                  ),
                ),

              // 3. Top Title & P2P / Cache Connection Status Bar
              if (_showControls && (widget.title != null || widget.p2pUrl != null || widget.cacheKey != null))
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.black.withOpacity(0.75),
                          Colors.black.withOpacity(0.2),
                          Colors.transparent,
                        ],
                      ),
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    child: Row(
                      children: [
                        if (widget.title != null)
                          Expanded(
                            child: Text(
                              widget.title!,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        const SizedBox(width: 8),
                        _buildConnectionBadge(),
                      ],
                    ),
                  ),
                ),

              // 4. Custom Aurora Floating Controller Bar
              if (_showControls)
                Positioned(
                  bottom: 0,
                  left: 0,
                  right: 0,
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.bottomCenter,
                        end: Alignment.topCenter,
                        colors: [
                          Colors.black.withOpacity(0.85),
                          Colors.black.withOpacity(0.4),
                          Colors.transparent,
                        ],
                      ),
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Progress Slider
                        SliderTheme(
                          data: SliderTheme.of(context).copyWith(
                            trackHeight: 3.5,
                            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                            overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
                            activeTrackColor: _isLocalCached ? const Color(0xFF10B981) : const Color(0xFF38BDF8),
                            inactiveTrackColor: Colors.white24,
                            thumbColor: Colors.white,
                          ),
                          child: Slider(
                            value: _position.inMilliseconds.toDouble().clamp(
                                  0.0,
                                  _duration.inMilliseconds.toDouble().clamp(0.1, double.infinity),
                                ),
                            max: _duration.inMilliseconds.toDouble().clamp(0.1, double.infinity),
                            onChanged: (val) {
                              _player.seek(Duration(milliseconds: val.toInt()));
                            },
                          ),
                        ),

                        // Controls Row
                        Row(
                          children: [
                            IconButton(
                              icon: Icon(
                                _isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                                color: Colors.white,
                                size: 24,
                              ),
                              onPressed: () => _player.playOrPause(),
                            ),
                            const SizedBox(width: 4),
                            Text(
                              '${_formatDuration(_position)} / ${_formatDuration(_duration)}',
                              style: const TextStyle(fontSize: 11.5, color: Colors.white70, fontFamily: 'monospace'),
                            ),
                            const SizedBox(width: 8),
                            _buildConnectionBadge(),
                            if (!_isLocalCached && !_isCaching && widget.cacheKey != null && widget.cacheKey!.isNotEmpty) ...[
                              const SizedBox(width: 4),
                              IconButton(
                                icon: const Icon(Icons.download_for_offline_outlined, color: Colors.white70, size: 18),
                                tooltip: '下载缓存到本地',
                                onPressed: () => _triggerBackgroundCache(_activeUrl ?? widget.streamUrl),
                              ),
                            ],
                            const Spacer(),
                            if (widget.onLaunchExternal != null)
                              IconButton(
                                icon: const Icon(Icons.open_in_new_rounded, color: Colors.white70, size: 18),
                                tooltip: '外接播放器播放',
                                onPressed: widget.onLaunchExternal,
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildConnectionBadge() {
    if (_isLocalCached) {
      return Tooltip(
        message: '正在使用本地磁盘缓存直接播放 (0 延时、无网络流量消耗)\n路径: ${_activeUrl ?? ""}',
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
          decoration: BoxDecoration(
            color: const Color(0xFF059669).withOpacity(0.25),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: const Color(0xFF10B981),
              width: 0.8,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  color: const Color(0xFF34D399),
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF34D399).withOpacity(0.6),
                      blurRadius: 4,
                      spreadRadius: 1,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 4.5),
              const Text(
                '💾 本地缓存 (秒开)',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFFD1FAE5),
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (_isCaching) {
      final percent = (_cacheProgress * 100).toInt().clamp(0, 100);
      return Tooltip(
        message: '视频正在后台边播边缓存到本地设备...\n已下载: ${_cacheProgress > 0 ? "$percent%" : "计算中"}',
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
          decoration: BoxDecoration(
            color: const Color(0xFF4F46E5).withOpacity(0.25),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: const Color(0xFF818CF8),
              width: 0.8,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 8,
                height: 8,
                child: CircularProgressIndicator(
                  strokeWidth: 1.5,
                  value: _cacheProgress > 0 ? _cacheProgress : null,
                  color: const Color(0xFFA5B4FC),
                ),
              ),
              const SizedBox(width: 5),
              Text(
                _cacheProgress > 0 ? '⏳ 缓存中 $percent%' : '⏳ 缓存中...',
                style: const TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFFE0E7FF),
                ),
              ),
            ],
          ),
        ),
      );
    }

    final isP2p = _isP2pActive;
    return Tooltip(
      message: isP2p
          ? '正在通过公网 IPv6 点对点直连播放 (无中继延迟)\n源: ${_activeUrl ?? widget.p2pUrl ?? ""}'
          : '正在通过中心服务器中继播放\n源: ${_activeUrl ?? widget.streamUrl}',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
        decoration: BoxDecoration(
          color: isP2p
              ? const Color(0xFF0284C7).withOpacity(0.3)
              : Colors.white.withOpacity(0.08),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isP2p ? const Color(0xFF38BDF8) : Colors.white24,
            width: 0.8,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                color: isP2p ? const Color(0xFF38BDF8) : const Color(0xFFF59E0B),
                shape: BoxShape.circle,
                boxShadow: isP2p
                    ? [
                        BoxShadow(
                          color: const Color(0xFF38BDF8).withOpacity(0.6),
                          blurRadius: 4,
                          spreadRadius: 1,
                        )
                      ]
                    : null,
              ),
            ),
            const SizedBox(width: 4.5),
            Text(
              isP2p ? '⚡ IPv6 直连 (P2P)' : '🌐 云端中继',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: isP2p ? const Color(0xFFE0F2FE) : Colors.white70,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
