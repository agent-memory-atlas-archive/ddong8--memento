import 'dart:async';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

class EmbeddedVideoPlayer extends StatefulWidget {
  final String streamUrl;
  final String? title;
  final VoidCallback? onLaunchExternal;

  const EmbeddedVideoPlayer({
    super.key,
    required this.streamUrl,
    this.title,
    this.onLaunchExternal,
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

  @override
  void initState() {
    super.initState();
    _initPlayer();
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

    _player.open(Media(widget.streamUrl), play: true);
    _startHideTimer();
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
    if (oldWidget.streamUrl != widget.streamUrl) {
      _errorMessage = null;
      _player.open(Media(widget.streamUrl), play: true);
    }
  }

  @override
  void dispose() {
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

              // 3. Custom Aurora Floating Controller Bar
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
                            activeTrackColor: const Color(0xFF38BDF8),
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
}
