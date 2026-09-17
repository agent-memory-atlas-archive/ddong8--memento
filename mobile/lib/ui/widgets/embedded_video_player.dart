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

  @override
  Widget build(BuildContext context) {
    if (_errorMessage != null) {
      return Center(
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: const Color(0xFF1E1010),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.redAccent.withOpacity(0.4)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline_rounded, color: Colors.redAccent, size: 36),
              const SizedBox(height: 10),
              const Text('媒体流加载异常', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              const SizedBox(height: 6),
              Text(_errorMessage!, style: const TextStyle(color: Colors.white70, fontSize: 12), textAlign: TextAlign.center),
              const SizedBox(height: 14),
              ElevatedButton.icon(
                onPressed: () {
                  setState(() => _errorMessage = null);
                  _player.open(Media(widget.streamUrl), play: true);
                },
                icon: const Icon(Icons.refresh, size: 16),
                label: const Text('重试播放'),
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
