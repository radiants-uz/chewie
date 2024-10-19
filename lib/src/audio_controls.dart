import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:just_audio/just_audio.dart';
import 'package:video_player/video_player.dart';

class MediaState {
  MediaState(this.mediaItem, this.position);
  final MediaItem? mediaItem;
  final Duration position;
}

class AudioPlayerHandler extends BaseAudioHandler with SeekHandler {
  AudioPlayerHandler();
  late StreamController<PlaybackState> streamController;

  MediaItem? media;
  AudioPlayer? _audioPlayer;
  Duration? _position;
  bool _isAudioPlaying = false;
  VideoPlayerController? _controller;

  late void Function(Duration)? _videoSeek;
  late void Function()? _videoPlay;
  late void Function()? _videoPause;
  late void Function()? _videoStop;

  void setMedia(MediaItem newMedia, AudioPlayer audioPlayer) {
    media = newMedia;
    _audioPlayer = audioPlayer;
    _audioPlayer?.createPositionStream();
    _audioPlayer?.setUrl(
      media!.id,
      tag: newMedia,
    );
  }

  Future<void> startBgPlay(
    Duration position,
    double speed,
    // ignore: avoid_positional_boolean_parameters
    bool isPlaying,
  ) async {
    _controller?.removeListener(addVideoEvent);
    _isAudioPlaying = true;
    await _audioPlayer?.seek(position);
    await _audioPlayer!.setSpeed(speed);

    if (isPlaying) {
      await _audioPlayer?.play();
    }
  }

  Duration? stopBgPlay() {
    final pos = _position;

    _isAudioPlaying = false;
    _audioPlayer?.stop();
    _controller?.addListener(addVideoEvent);

    return pos;
  }

  void setVideoFunctions(
    void Function() play,
    void Function() pause,
    void Function(Duration duration) seek,
    void Function() stop,
  ) {
    _videoPlay = play;
    _videoPause = pause;
    _videoSeek = seek;
    _videoStop = stop;
    mediaItem.add(media);
  }

  // In this simple example, we handle only 4 actions: play, pause, seek and
  // stop. Any button press from the Flutter UI, notification, lock screen or
  // headset will be routed through to these 4 methods so that you can handle
  // your audio playback logic in one place.

  @override
  Future<void> play() async {
    if (_isAudioPlaying) {
      await _audioPlayer!.play();
      return;
    }
    _videoPlay!();
  }

  @override
  Future<void> pause() async {
    if (_isAudioPlaying) {
      await _audioPlayer!.pause();
      return;
    }
    _videoPause!();
  }

  @override
  Future<void> seek(Duration position) async {
    if (_isAudioPlaying) {
      await _audioPlayer!.seek(position);
      return;
    }
    _videoSeek!(position);
  }

  @override
  Future<void> stop() async {
    if (_isAudioPlaying) {
      await _audioPlayer!.seek(Duration.zero);
      return;
    }
    _videoStop!();
  }

  void dispose() {
    streamController.add(
      PlaybackState(),
    );
  }

  bool isPlaying() => _isAudioPlaying
      ? _audioPlayer?.playing ?? false
      : _controller?.value.isPlaying ?? false;

  AudioProcessingState processingState() {
    if (_controller == null) return AudioProcessingState.idle;
    if (_controller!.value.isInitialized) {
      return AudioProcessingState.ready;
    }
    return AudioProcessingState.idle;
  }

  Duration bufferedPosition() {
    if (_audioPlayer != null && _isAudioPlaying) {
      try {
        return _audioPlayer!.bufferedPosition;
      } catch (err) {
        return Duration.zero;
      }
    }

    try {
      final currentBufferedRange =
          _controller?.value.buffered.firstWhere((durationRange) {
        final position = _controller!.value.position;
        final isCurrentBufferedRange =
            durationRange.start < position && durationRange.end > position;
        return isCurrentBufferedRange;
      });
      if (currentBufferedRange == null) return Duration.zero;
      return currentBufferedRange.end;
    } catch (err) {
      return Duration.zero;
    }
  }

  void addVideoEvent() {
    streamController.add(
      PlaybackState(
        controls: [
          MediaControl.rewind,
          if (isPlaying()) MediaControl.pause else MediaControl.play,
          MediaControl.stop,
          MediaControl.fastForward,
        ],
        systemActions: const {
          MediaAction.seek,
          MediaAction.seekForward,
          MediaAction.seekBackward,
        },
        androidCompactActionIndices: const [0, 1, 3],
        processingState: processingState(),
        playing: isPlaying(),
        updatePosition: (_isAudioPlaying
                ? _audioPlayer?.position
                : _controller?.value.position) ??
            Duration.zero,
        bufferedPosition: bufferedPosition(),
        speed: _controller?.value.playbackSpeed ?? 1.0,
      ),
    );
  }

  void startStream() {
    _controller?.addListener(addVideoEvent);
    _audioPlayer?.playbackEventStream.listen((data) {
      if (_isAudioPlaying) {
        addVideoEvent();
      }
    });
    _audioPlayer?.positionStream.listen((position) {
      if (_isAudioPlaying) {
        _position = position;
        if (position.inSeconds != _controller?.value.position.inSeconds) {
          _batchUpdatePosition(position);
        }
      }
    });
  }

  void stopStream() {
    _controller?.removeListener(addVideoEvent);
    streamController.close();
  }

  Timer? _batchUpdateTimer;

  void _batchUpdatePosition(Duration position) {
    _batchUpdateTimer ??= Timer(const Duration(seconds: 1), () async {
      await _controller?.seekTo(position);
      _batchUpdateTimer = null;
    });
  }

  void initializeStreamController({
    VideoPlayerController? videoPlayerController,
  }) {
    _controller = videoPlayerController;

    streamController = StreamController<PlaybackState>(
      onListen: startStream,
      onPause: stopStream,
      onResume: startStream,
      onCancel: stopStream,
    );
  }
}
