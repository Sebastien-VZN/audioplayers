import 'dart:async';
import 'dart:js_interop';

import 'package:audioplayers_platform_interface/audioplayers_platform_interface.dart';
import 'package:audioplayers_web/num_extension.dart';
import 'package:flutter/services.dart';
import 'package:web/web.dart' as web;

class WrappedPlayer {
  WrappedPlayer(this.playerId);
  final String playerId;
  final eventStreamController = StreamController<AudioEvent>.broadcast();

  double? _pausedAt;
  double _currentVolume = 1;
  double _currentPlaybackRate = 1;
  ReleaseMode _currentReleaseMode = ReleaseMode.release;
  String? _currentUrl;
  bool _isPlaying = false;

  web.HTMLAudioElement? player;
  web.AudioContext? _audioContext;
  web.MediaElementAudioSourceNode? _sourceNode;
  web.StereoPannerNode? _stereoPanner;
  StreamSubscription<web.Event>? _playerEndedSubscription;
  StreamSubscription<web.Event>? _playerLoadedDataSubscription;
  StreamSubscription<web.Event>? _playerPlaySubscription;
  StreamSubscription<web.Event>? _playerSeekedSubscription;
  StreamSubscription<web.Event>? _playerErrorSubscription;

  Future<void> setUrl(String url) async {
    if (_currentUrl == url) {
      eventStreamController.add(
        const AudioEvent(eventType: AudioEventType.prepared, isPrepared: true),
      );
      return;
    }
    _currentUrl = url;

    await release();
    recreateNode();
    if (_isPlaying) {
      await resume();
    }
  }

  void volume(double volume) {
    _currentVolume = volume;
    player?.volume = volume;
  }

  double get balance => _stereoPanner?.pan.value ?? 0.0;
  set balance(double balance) {
    if (_stereoPanner != null) _stereoPanner!.pan.value = balance;
  }

  void playbackRate(double rate) {
    _currentPlaybackRate = rate;
    player?.playbackRate = rate;
  }

  void recreateNode() {
    final currentUrl = _currentUrl;
    if (currentUrl == null) {
      return;
    }

    final p = player = web.HTMLAudioElement()
      ..preload = 'auto'
      ..src = currentUrl
      // As the AudioElement is created dynamically via script,
      // features like 'stereo panning' need the CORS header to be enabled.
      // See: https://developer.mozilla.org/en-US/docs/Web/HTTP/CORS
      ..crossOrigin = 'anonymous'
      ..loop = shouldLoop()
      ..volume = _currentVolume
      ..playbackRate = _currentPlaybackRate;

    _setupStreams(p);

    // Reuse or create AudioContext (Safari limits concurrent contexts)
    _audioContext ??= web.AudioContext();

    final source = _audioContext!.createMediaElementSource(p);
    _sourceNode = source;
    _stereoPanner = _audioContext!.createStereoPanner();
    source.connect(_stereoPanner!);
    _stereoPanner?.connect(_audioContext!.destination);

    // Preload the source
    p.load();
  }

  void _setupStreams(web.HTMLAudioElement p) {
    _playerLoadedDataSubscription = p.onLoadedData.listen(
      (_) {
        eventStreamController
          ..add(
            const AudioEvent(
              eventType: AudioEventType.prepared,
              isPrepared: true,
            ),
          )
          ..add(
            AudioEvent(
              eventType: AudioEventType.duration,
              duration: p.duration.fromSecondsToDuration(),
            ),
          );
      },
      onError: eventStreamController.addError,
    );
    _playerPlaySubscription = p.onPlay.listen(
      (_) {
        eventStreamController.add(
          AudioEvent(
            eventType: AudioEventType.duration,
            duration: p.duration.fromSecondsToDuration(),
          ),
        );
      },
      onError: eventStreamController.addError,
    );
    _playerSeekedSubscription = p.onSeeked.listen(
      (_) {
        eventStreamController.add(
          const AudioEvent(
            eventType: AudioEventType.seekComplete,
          ),
        );
      },
      onError: eventStreamController.addError,
    );
    _playerEndedSubscription = p.onEnded.listen(
      (_) async {
        if (_currentReleaseMode == ReleaseMode.release) {
          await release();
        } else {
          await stop();
        }
        eventStreamController.add(
          const AudioEvent(
            eventType: AudioEventType.complete,
          ),
        );
      },
      onError: eventStreamController.addError,
    );
    _playerErrorSubscription = p.onError.listen(
      (_) {
        String platformMsg;
        if (p.error != null) {
          platformMsg = 'Failed to set source.';
        } else {
          platformMsg = 'Unknown web error. See details.';
        }
        eventStreamController.addError(
          PlatformException(
            code: 'WebAudioError',
            message: platformMsg,
            details:
                '${p.error?.runtimeType}: '
                '${p.error?.message} (Code: ${p.error?.code})',
          ),
        );
      },
      onError: eventStreamController.addError,
    );
  }

  bool shouldLoop() => _currentReleaseMode == ReleaseMode.loop;

  void releaseMode(ReleaseMode releaseMode) {
    _currentReleaseMode = releaseMode;
    player?.loop = shouldLoop();
  }

  Future<void> release() async {
    pause();
    // Need to reset pausedAt, otherwise resume will start at the old position
    // after release.
    _pausedAt = null;

    _sourceNode?.disconnect();
    _sourceNode = null;
    // Release `AudioElement` correctly (#966)
    player?.src = '';
    player?.remove();
    player = null;
    _stereoPanner = null;

    await _playerLoadedDataSubscription?.cancel();
    _playerLoadedDataSubscription = null;
    await _playerEndedSubscription?.cancel();
    _playerEndedSubscription = null;
    await _playerSeekedSubscription?.cancel();
    _playerSeekedSubscription = null;
    await _playerPlaySubscription?.cancel();
    _playerPlaySubscription = null;
    await _playerErrorSubscription?.cancel();
    _playerErrorSubscription = null;
  }

  Future<void> start(double position) async {
    _isPlaying = true;
    if (_currentUrl == null) {
      return; // nothing to play yet
    }
    if (player == null) {
      recreateNode();
    }

    // Safari requires explicit resume after user gesture
    if (_audioContext != null && _audioContext!.state == 'suspended') {
      await _audioContext!.resume().toDart;
    }

    player?.currentTime = position;
    await player?.play().toDart;
  }

  Future<void> resume() async {
    await start(_pausedAt ?? 0);
  }

  void pause() {
    if (player == null) return;
    _pausedAt = double.tryParse(player!.currentTime.toString()) ?? 0;
    _isPlaying = false;
    player?.pause();
  }

  Future<void> stop() async {
    pause();
    _pausedAt = 0;
    if (_currentReleaseMode == ReleaseMode.release) {
      await release();
    } else {
      player?.currentTime = 0;
    }
  }

  void seek(int position) {
    final seekPosition = position / 1000.0;
    player?.currentTime = seekPosition;

    if (!_isPlaying) {
      _pausedAt = seekPosition;
    }
  }

  void log(String message) {
    eventStreamController.add(
      AudioEvent(eventType: AudioEventType.log, logMessage: message),
    );
  }

  Future<void> dispose() async {
    await release();
    await _audioContext?.close().toDart;
    _audioContext = null;
    await eventStreamController.close();
  }
}
