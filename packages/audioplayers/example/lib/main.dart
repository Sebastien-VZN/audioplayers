import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:audioplayers_example/components/tabs.dart';
import 'package:audioplayers_example/components/tgl.dart';
import 'package:audioplayers_example/tabs/audio_context.dart';
import 'package:audioplayers_example/tabs/controls.dart';
import 'package:audioplayers_example/tabs/logger.dart';
import 'package:audioplayers_example/tabs/sources.dart';
import 'package:audioplayers_example/tabs/streams.dart';
import 'package:audioplayers_example/utils.dart';
import 'package:flutter/material.dart';

const defaultPlayerCount = 4;

typedef OnError = void Function(Exception exception);

/// The app is deployed at: https://Sebastien-VZN.github.io/audioplayers/
void main() {
  runApp(const MaterialApp(home: _ExampleApp()));
}

class _ExampleApp extends StatefulWidget {
  const _ExampleApp();

  @override
  _ExampleAppState createState() => _ExampleAppState();
}

class _ExampleAppState extends State<_ExampleApp> {
  Future<bool>? _initFuture;
  late List<AudioPlayer> audioPlayers;
  int selectedPlayerIdx = 0;
  AudioPlayer get selectedAudioPlayer => audioPlayers[selectedPlayerIdx];
  List<StreamSubscription<dynamic>> streams = [];

  @override
  void initState() {
    super.initState();
    _initFuture = _init();
  }

  @override
  void dispose() {
    unawaited(close());
    super.dispose();
  }

  Future<bool> _init() async {
    audioPlayers = await Future.wait(
      List.generate(
        defaultPlayerCount,
        (_) async {
          final player = AudioPlayer();

          await player.setReleaseMode(ReleaseMode.stop);
          return player;
        },
      ),
    );

    if (audioPlayers.isNotEmpty) {
      audioPlayers.asMap().forEach((index, player) {
        streams
          ..add(
            player.onPlayerStateChanged.listen((it) {
              switch (it) {
                case PlayerState.stopped:
                  toast(
                    'Player stopped!',
                    textKey: Key('toast-player-stopped-$index'),
                  );
                case PlayerState.completed:
                  toast(
                    'Player complete!',
                    textKey: Key('toast-player-complete-$index'),
                  );

                case PlayerState.playing:
                case PlayerState.paused:
                case PlayerState.disposed:
              }
            }),
          )
          ..add(
            player.onSeekComplete.listen(
              (it) => toast(
                'Seek complete!',
                textKey: Key('toast-seek-complete-$index'),
              ),
            ),
          );
      });
      return true;
    }

    return false;
  }

  Future<void> close() async {
    for (final it in streams) {
      await it.cancel();
    }
  }

  Future<void> _handleAction(PopupAction value) async {
    switch (value) {
      case PopupAction.add:
        final player = AudioPlayer();
        await player.setReleaseMode(ReleaseMode.stop);
        audioPlayers.add(player);
        setState(() {});
      case PopupAction.remove:
        if (audioPlayers.isNotEmpty) {
          await selectedAudioPlayer.dispose();
          audioPlayers.removeAt(selectedPlayerIdx);
        }
        // Adjust index to be in valid range
        if (audioPlayers.isEmpty) {
          selectedPlayerIdx = 0;
        } else if (selectedPlayerIdx >= audioPlayers.length) {
          selectedPlayerIdx = audioPlayers.length - 1;
        }
        setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('AudioPlayers example'),
        actions: [
          PopupMenuButton<PopupAction>(
            onSelected: _handleAction,
            itemBuilder: (context) {
              return PopupAction.values.map((choice) {
                return PopupMenuItem<PopupAction>(
                  value: choice,
                  child: Text(
                    choice == PopupAction.add
                        ? 'Add player'
                        : 'Remove selected player',
                  ),
                );
              }).toList();
            },
          ),
        ],
      ),
      body: FutureBuilder<void>(
        future: _initFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return Center(child: Text('Erreur: ${snapshot.error}'));
          }

          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(8),
                child: Center(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Tgl(
                      key: const Key('playerTgl'),
                      options: [
                        for (var i = 1; i <= audioPlayers.length; i++) i,
                      ]
                          .asMap()
                          .map((key, val) => MapEntry('player-$key', 'P$val')),
                      selected: selectedPlayerIdx,
                      onChange: (v) => setState(() => selectedPlayerIdx = v),
                    ),
                  ),
                ),
              ),
              Expanded(
                child: audioPlayers.isEmpty
                    ? const Text('No AudioPlayer available!')
                    : IndexedStack(
                        index: selectedPlayerIdx,
                        children: audioPlayers
                            .map(
                              (player) => Tabs(
                                key: GlobalObjectKey(player),
                                tabs: [
                                  TabData(
                                    key: 'sourcesTab',
                                    label: 'Src',
                                    content: SourcesTab(player: player),
                                  ),
                                  TabData(
                                    key: 'controlsTab',
                                    label: 'Ctrl',
                                    content: ControlsTab(player: player),
                                  ),
                                  TabData(
                                    key: 'streamsTab',
                                    label: 'Stream',
                                    content: StreamsTab(player: player),
                                  ),
                                  TabData(
                                    key: 'audioContextTab',
                                    label: 'Ctx',
                                    content: AudioContextTab(player: player),
                                  ),
                                  TabData(
                                    key: 'loggerTab',
                                    label: 'Log',
                                    content: LoggerTab(player: player),
                                  ),
                                ],
                              ),
                            )
                            .toList(),
                      ),
              ),
            ],
          );
        },
      ),
    );
  }
}

enum PopupAction { add, remove }
