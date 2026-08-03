// Tests liés à l'issue #1979 — Crash Windows quand pas de périphérique audio.
//
// Ces tests valident que la couche Flutter gère correctement les erreurs
// remontées par le code natif (C++) quand MediaFoundation ne trouve pas
// de renderer audio (pas de device, service désactivé, VM, RDP).
//
// Le code C++ du fork capture ces erreurs via try-catch global sur
// HandleMethodCall et les remonte via result->Error("WindowsAudioError", ...).
// Côté Dart, _create() catch Exception → creatingCompleter.completeError,
// et les erreurs runtime sont captées par AudioLogger.error().
//
// Référence : references/windows-error-handling.md (skill axomind_audioplayers)

import 'dart:async';
import 'package:audioplayers/audioplayers.dart';
import 'package:audioplayers_platform_interface/audioplayers_platform_interface.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class MockAudioplayersPlatform extends Mock with MockPlatformInterfaceMixin implements AudioplayersPlatformInterface {}

class MockGlobalAudioplayersPlatform extends Mock with MockPlatformInterfaceMixin implements GlobalAudioplayersPlatformInterface {}

class MockAudioCache extends Mock implements AudioCache {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    registerFallbackValue(Uint8List(0));
    registerFallbackValue(const Duration(seconds: 1));
    registerFallbackValue(PlayerMode.mediaPlayer);
    registerFallbackValue(ReleaseMode.release);
  });

  late MockAudioplayersPlatform mockPlatform;
  late MockGlobalAudioplayersPlatform mockGlobalPlatform;
  late MockAudioCache mockCache;
  late StreamController<AudioEvent> eventController;

  setUp(() {
    // Désactiver les logs globalement pour éviter que AudioLogger.error →
    // debugPrint soit intercepté par le framework de test comme une erreur
    // non gérée pendant les tests d'erreur.
    AudioLogger.logLevel = AudioLogLevel.none;

    mockPlatform = MockAudioplayersPlatform();
    AudioplayersPlatformInterface.instance = mockPlatform;

    mockGlobalPlatform = MockGlobalAudioplayersPlatform();
    GlobalAudioplayersPlatformInterface.instance = mockGlobalPlatform;

    mockCache = MockAudioCache();

    eventController = StreamController<AudioEvent>.broadcast();

    // Stubbing global platform
    when(() => mockGlobalPlatform.init()).thenAnswer((_) async {});
    when(
      () => mockGlobalPlatform.getGlobalEventStream(),
    ).thenAnswer((_) => const Stream<GlobalAudioEvent>.empty());

    // Stubbing player platform basic methods
    when(() => mockPlatform.create(any())).thenAnswer((_) async {});
    when(
      () => mockPlatform.getEventStream(any()),
    ).thenAnswer((_) => eventController.stream);
    when(() => mockPlatform.dispose(any())).thenAnswer((_) async {});
    when(
      () => mockPlatform.setSourceUrl(
        any(),
        any(),
        isLocal: any(named: 'isLocal'),
        mimeType: any(named: 'mimeType'),
      ),
    ).thenAnswer((_) async {});
    when(
      () => mockPlatform.setSourceBytes(
        any(),
        any(),
        mimeType: any(named: 'mimeType'),
      ),
    ).thenAnswer((_) async {});
    when(() => mockPlatform.resume(any())).thenAnswer((_) async {});
    when(() => mockPlatform.pause(any())).thenAnswer((_) async {});
    when(() => mockPlatform.stop(any())).thenAnswer((_) async {});
    when(() => mockPlatform.release(any())).thenAnswer((_) async {});
    when(() => mockPlatform.seek(any(), any())).thenAnswer((_) async {});
    when(() => mockPlatform.setVolume(any(), any())).thenAnswer((_) async {});
    when(() => mockPlatform.setBalance(any(), any())).thenAnswer((_) async {});
    when(
      () => mockPlatform.setPlaybackRate(any(), any()),
    ).thenAnswer((_) async {});
    when(
      () => mockPlatform.getCurrentPosition(any()),
    ).thenAnswer((_) async => 0);
    when(() => mockPlatform.getDuration(any())).thenAnswer((_) async => 0);
  });

  tearDown(() async {
    await eventController.close();
  });

  group('Issue #1979 — No audio device (creation failure)', () {
    test(
      'Player creation with PlatformException does not crash the app',
      () async {
        // Simule l'échec de création du player côté natif (pas de device audio).
        // Le code C++ lance result->Error("WindowsAudioError", ...) qui remonte
        // comme PlatformException côté Dart.
        when(() => mockPlatform.create(any())).thenThrow(
          PlatformException(
            code: 'WindowsAudioError',
            message: 'Failed to create audio player.',
            details: 'MediaEngine creation failed (no audio device).',
          ),
        );

        final player = AudioPlayer()..audioCache = mockCache;

        // _create() catch Exception → creatingCompleter.completeError.
        // L'erreur doit être captée, pas propagée comme crash non géré.
        expect(
          player.creatingCompleter.future,
          throwsA(
            isA<PlatformException>().having(
              (e) => e.code,
              'code',
              'WindowsAudioError',
            ),
          ),
        );

        // Le player ne doit pas crasher — il reste dans l'état initial.
        await expectLater(
          player.creatingCompleter.future,
          throwsA(isA<PlatformException>()),
        );
      },
    );

    test('play() after creation failure logs error without crashing', () async {
      when(() => mockPlatform.create(any())).thenThrow(
        PlatformException(
          code: 'WindowsAudioError',
          message: 'Failed to create audio player.',
        ),
      );

      final player = AudioPlayer()..audioCache = mockCache;

      // Attendre que le completer échoue.
      await expectLater(
        player.creatingCompleter.future,
        throwsA(isA<PlatformException>()),
      );

      // play() doit échouer gracieusement (creatingCompleter déjà en erreur).
      // L'erreur ne doit pas crasher le test.
      await expectLater(
        player.play(UrlSource('https://example.com/audio.mp3')),
        throwsA(isA<Exception>()),
      );
    });
  });

  group('Issue #1979 — No audio device (playback failure)', () {
    test('resume() with PlatformException does not crash the app', () async {
      // Le player est créé avec succès (le MediaEngine peut s'initialiser
      // même sans device), mais resume() échoue au moment du Play().
      final player = AudioPlayer()..audioCache = mockCache;
      await player.creatingCompleter.future;

      // Simule l'échec de resume() côté natif.
      when(() => mockPlatform.resume(any())).thenThrow(
        PlatformException(
          code: 'WindowsAudioError',
          message: 'Playback error',
          details: 'Échec de la création de mediasink (Code: 4)',
        ),
      );

      // resume() doit propager l'Exception (pas la laisser non gérée).
      // En production, l'appelant (play() ou _completePrepared) catch l'erreur.
      expect(
        player.resume(),
        throwsA(
          isA<PlatformException>().having(
            (e) => e.code,
            'code',
            'WindowsAudioError',
          ),
        ),
      );
    });

    test(
      'play() catches PlatformException on resume and logs via AudioLogger',
      () async {
        final player = AudioPlayer()..audioCache = mockCache;
        await player.creatingCompleter.future;

        // setSourceUrl réussit, mais resume échoue.
        when(() => mockPlatform.resume(any())).thenThrow(
          PlatformException(
            code: 'WindowsAudioError',
            message: 'Playback error',
            details: 'Échec de la création de mediasink (Code: 4)',
          ),
        );

        // play() appelle _completePrepared qui a un try-catch (ligne 388).
        // L'erreur doit être captée par AudioLogger.error, pas propagée.
        final playFuture = player.play(
          UrlSource('https://example.com/audio.mp3'),
        );

        // Simuler l'événement prepared pour débloquer le Future.wait.
        await Future<void>.delayed(const Duration(milliseconds: 100));
        eventController.add(
          const AudioEvent(
            eventType: AudioEventType.prepared,
            isPrepared: true,
          ),
        );

        // play() doit compléter sans crasher (erreur captée en interne).
        await playFuture;

        // Le player doit toujours être utilisable.
        expect(player.state, isNot(PlayerState.disposed));
      },
    );

    test('BytesSource playback failure does not crash', () async {
      final player = AudioPlayer()..audioCache = mockCache;
      await player.creatingCompleter.future;

      when(() => mockPlatform.resume(any())).thenThrow(
        PlatformException(
          code: 'WindowsAudioError',
          message: 'Playback error',
          details: 'Échec de la création de mediasink (Code: 4)',
        ),
      );

      final bytes = Uint8List.fromList([0, 1, 2, 3, 4, 5, 6, 7]);
      final playFuture = player.play(
        BytesSource(bytes, mimeType: 'audio/mpeg'),
      );

      await Future<void>.delayed(const Duration(milliseconds: 100));
      eventController.add(
        const AudioEvent(eventType: AudioEventType.prepared, isPrepared: true),
      );

      // Doit compléter sans crasher.
      await playFuture;
      expect(player.state, isNot(PlayerState.disposed));
    });
  });

  group('Issue #1979 — Error stream handling', () {
    test('Platform error on event stream does not crash player', () async {
      final player = AudioPlayer()..audioCache = mockCache;
      await player.creatingCompleter.future;

      // Simule une erreur asynchrone du MediaEngine (callback OnMediaError).
      eventController.addError(
        PlatformException(
          code: 'WindowsAudioError',
          message: 'Playback error',
          details: 'Échec de la création de mediasink (Code: 4)',
        ),
      );

      // Le player doit rester vivant — l'erreur est captée par
      // AudioLogger.error via le onError du stream (ligne 186-191).
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(player.state, isNot(PlayerState.disposed));
    });

    test('Multiple sequential errors do not crash player', () async {
      final player = AudioPlayer()..audioCache = mockCache;
      await player.creatingCompleter.future;

      for (var i = 0; i < 5; i++) {
        eventController.addError(
          PlatformException(
            code: 'WindowsAudioError',
            message: 'Playback error attempt $i',
          ),
        );
      }

      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(player.state, isNot(PlayerState.disposed));
    });
  });
}
