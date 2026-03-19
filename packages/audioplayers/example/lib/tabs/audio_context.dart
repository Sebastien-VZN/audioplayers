import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:audioplayers_example/components/cbx.dart';
import 'package:audioplayers_example/components/drop_down.dart';
import 'package:audioplayers_example/components/tab_content.dart';
import 'package:audioplayers_example/components/tabs.dart';
import 'package:audioplayers_example/utils.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

class AudioContextTab extends StatefulWidget {
  const AudioContextTab({required this.player, super.key});
  final AudioPlayer player;

  @override
  AudioContextTabState createState() => AudioContextTabState();
}

class AudioContextTabState extends State<AudioContextTab>
    with AutomaticKeepAliveClientMixin<AudioContextTab> {
  static GlobalAudioScope get _global => AudioPlayer.global;

  AudioPlayer get player => widget.player;

  /// Set config for all platforms
  AudioContextConfig audioContextConfig = AudioContextConfig();

  /// Set config for each platform individually
  AudioContext audioContext = AudioContext();

  bool isLocal = true;
  bool isGlobal = false;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Column(
      children: [
        const ListTile(title: Text('Audio Context')),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            ToggleButtons(
              isSelected: [isGlobal, isLocal],
              onPressed: (index) {
                if (index == 0) {
                  setState(() {
                    isGlobal = !isGlobal;
                  });
                } else if (index == 1) {
                  setState(() {
                    isLocal = !isLocal;
                  });
                }
              },
              borderRadius: const BorderRadius.all(Radius.circular(8)),
              selectedBorderColor: Theme.of(context).primaryColor,
              children: const [
                Padding(padding: EdgeInsets.all(8), child: Text('Global')),
                Padding(padding: EdgeInsets.all(8), child: Text('Local')),
              ],
            ),
            ElevatedButton.icon(
              icon: const Icon(Icons.undo),
              label: const Text('Reset'),
              onPressed: () => updateConfig(AudioContextConfig()),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Expanded(
          child: Tabs(
            tabs: [
              TabData(
                key: 'contextTab-genericFlags',
                label: 'Generic Flags',
                content: _genericTab(),
              ),
              if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android)
                TabData(
                  key: 'contextTab-android',
                  label: 'Android',
                  content: _androidTab(),
                ),
              if (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS)
                TabData(
                  key: 'contextTab-ios',
                  label: 'iOS',
                  content: _iosTab(),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> updateConfig(AudioContextConfig newConfig) async {
    try {
      final context = newConfig.build();
      audioContextConfig = newConfig;
      audioContext = context;
      await _applyAudioContext(audioContext);
      setState(() {});
    } on Exception catch (e) {
      toast(e.toString());
    }
  }

  Future<void> updateAudioContextAndroid(
    AudioContextAndroid contextAndroid,
  ) async {
    audioContext = audioContext.copy(android: contextAndroid);
    await _applyAudioContext(audioContext);
    setState(() {});
  }

  Future<void> updateAudioContextIOS(
    AudioContextIOS Function() buildContextIOS,
  ) async {
    try {
      final context = buildContextIOS();
      audioContext = audioContext.copy(iOS: context);
      await _applyAudioContext(audioContext);
      setState(() {});
    } on Exception catch (e) {
      toast(e.toString());
    }
  }

  Future<void> _applyAudioContext(AudioContext context) async {
    if (isGlobal) {
      await _global.setAudioContext(context);
    }
    if (isLocal) {
      await player.setAudioContext(context);
    }
  }

  Widget _genericTab() {
    return TabContent(
      children: [
        LabeledDropDown<AudioContextConfigRoute>(
          label: 'Audio Route',
          key: const Key('audioRoute'),
          options: {for (final e in AudioContextConfigRoute.values) e: e.name},
          selected: audioContextConfig.route,
          onChange: (v) => updateConfig(audioContextConfig.copy(route: v)),
        ),
        LabeledDropDown<AudioContextConfigFocus>(
          label: 'Audio Focus',
          key: const Key('audioFocus'),
          options: {for (final e in AudioContextConfigFocus.values) e: e.name},
          selected: audioContextConfig.focus,
          onChange: (v) => updateConfig(audioContextConfig.copy(focus: v)),
        ),
        Cbx(
          'Respect Silence',
          value: audioContextConfig.respectSilence,
          ({value}) =>
              updateConfig(audioContextConfig.copy(respectSilence: value)),
        ),
        Cbx(
          'Stay Awake',
          value: audioContextConfig.stayAwake,
          ({value}) => updateConfig(audioContextConfig.copy(stayAwake: value)),
        ),
      ],
    );
  }

  Widget _androidTab() {
    return TabContent(
      children: [
        Cbx(
          'isSpeakerphoneOn',
          value: audioContext.android.isSpeakerphoneOn,
          ({value}) => updateAudioContextAndroid(
            audioContext.android.copy(isSpeakerphoneOn: value),
          ),
        ),
        Cbx(
          'stayAwake',
          value: audioContext.android.stayAwake,
          ({value}) => updateAudioContextAndroid(
            audioContext.android.copy(stayAwake: value),
          ),
        ),
        LabeledDropDown<AndroidContentType>(
          label: 'contentType',
          key: const Key('contentType'),
          options: {for (final e in AndroidContentType.values) e: e.name},
          selected: audioContext.android.contentType,
          onChange: (v) => updateAudioContextAndroid(
            audioContext.android.copy(contentType: v),
          ),
        ),
        LabeledDropDown<AndroidUsageType>(
          label: 'usageType',
          key: const Key('usageType'),
          options: {for (final e in AndroidUsageType.values) e: e.name},
          selected: audioContext.android.usageType,
          onChange: (v) => updateAudioContextAndroid(
            audioContext.android.copy(usageType: v),
          ),
        ),
        LabeledDropDown<AndroidAudioFocus?>(
          key: const Key('audioFocus'),
          label: 'audioFocus',
          options: {for (final e in AndroidAudioFocus.values) e: e.name},
          selected: audioContext.android.audioFocus,
          onChange: (v) => updateAudioContextAndroid(
            audioContext.android.copy(audioFocus: v),
          ),
        ),
        LabeledDropDown<AndroidAudioMode>(
          key: const Key('audioMode'),
          label: 'audioMode',
          options: {for (final e in AndroidAudioMode.values) e: e.name},
          selected: audioContext.android.audioMode,
          onChange: (v) => updateAudioContextAndroid(
            audioContext.android.copy(audioMode: v),
          ),
        ),
      ],
    );
  }

  Widget _iosTab() {
    final iosOptions = AVAudioSessionOptions.values.map((option) {
      final options = {...audioContext.iOS.options};
      return Cbx(option.name, value: options.contains(option), ({value}) {
        unawaited(
          updateAudioContextIOS(() {
            final iosContext = audioContext.iOS.copy(options: options);
            if (value ?? false) {
              options.add(option);
            } else {
              options.remove(option);
            }
            return iosContext;
          }),
        );
      });
    }).toList();
    return TabContent(
      children: <Widget>[
        LabeledDropDown<AVAudioSessionCategory>(
          key: const Key('category'),
          label: 'category',
          options: {for (final e in AVAudioSessionCategory.values) e: e.name},
          selected: audioContext.iOS.category,
          onChange: (v) =>
              updateAudioContextIOS(() => audioContext.iOS.copy(category: v)),
        ),
        ...iosOptions,
      ],
    );
  }

  @override
  bool get wantKeepAlive => true;
}
