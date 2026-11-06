import 'dart:async';

import 'package:animated_bottom_navigation_bar/animated_bottom_navigation_bar.dart';
import 'package:chewie/chewie.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:video_player/video_player.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';

/// Reports the video as immediately ready, so Chewie builds its real controls.
class _FakeVideoPlayerPlatform extends VideoPlayerPlatform {
  final _events = <int, StreamController<VideoEvent>>{};
  int _nextId = 0;

  @override
  Future<void> init() async {}

  @override
  Future<int?> createWithOptions(VideoCreationOptions options) async {
    final id = _nextId++;
    _events[id] = StreamController<VideoEvent>()
      ..add(
        VideoEvent(
          eventType: VideoEventType.initialized,
          duration: const Duration(seconds: 10),
          size: const Size(1920, 1080),
        ),
      );
    return id;
  }

  @override
  Stream<VideoEvent> videoEventsFor(int playerId) => _events[playerId]!.stream;

  @override
  Future<void> dispose(int playerId) async => _events.remove(playerId);

  @override
  Future<void> setLooping(int playerId, bool looping) async {}

  @override
  Future<void> play(int playerId) async {}

  @override
  Future<void> pause(int playerId) async {}

  @override
  Future<void> setVolume(int playerId, double volume) async {}

  @override
  Future<void> setPlaybackSpeed(int playerId, double speed) async {}

  @override
  Future<void> seekTo(int playerId, Duration position) async {}

  @override
  Future<Duration> getPosition(int playerId) async => Duration.zero;

  @override
  Widget buildViewWithOptions(VideoViewOptions options) => const SizedBox();

  @override
  Future<void> setMixWithOthers(bool mixWithOthers) async {}
}

/// The analyzer cannot see the failures these guard against: a package built on
/// `package:flutter/material.dart` looks up that library's Scaffold, Material,
/// Theme and Localizations, so it can compile and still throw when it builds
/// under the app's `material_ui` shell.
Widget _shell({required Widget body, Widget? bottomNavigationBar}) =>
    MaterialApp(
      // ignore: deprecated_member_use
      builder: (context, child) => MaterialUiCompatibilityBridge(child: child!),
      home: Scaffold(body: body, bottomNavigationBar: bottomNavigationBar),
    );

void main() {
  testWidgets(
    'Chewie controls build and respond',
    (tester) async {
      VideoPlayerPlatform.instance = _FakeVideoPlayerPlatform();
      final video = VideoPlayerController.networkUrl(
        Uri.parse('https://example.test/video.mp4'),
      );
      await tester.runAsync(video.initialize);
      final chewie = ChewieController(
        videoPlayerController: video,
        aspectRatio: 16 / 9,
        showControlsOnInitialize: true,
        allowPlaybackSpeedChanging: true,
        playbackSpeeds: const [0.5, 1.0],
      );

      await tester.pumpWidget(_shell(body: Chewie(controller: chewie)));
      await tester.pump();
      expect(tester.takeException(), isNull);

      // Chewie's IconButton is the framework's, so byType cannot name it here.
      final buttons = find.byWidgetPredicate(
        (widget) => widget.runtimeType.toString() == 'IconButton',
      );
      for (final element in buttons.evaluate().toList()) {
        await tester.tap(find.byWidget(element.widget), warnIfMissed: false);
        await tester.pump();
        expect(tester.takeException(), isNull);
      }

      await tester.pumpWidget(const SizedBox());
      chewie.dispose();
      await tester.runAsync(video.dispose);
      await tester.pump(const Duration(seconds: 5));
    },
    variant: const TargetPlatformVariant({
      TargetPlatform.android,
      TargetPlatform.iOS,
      TargetPlatform.macOS,
    }),
  );

  testWidgets('ColorPicker hex field builds and takes focus', (tester) async {
    await tester.pumpWidget(
      _shell(
        body: AlertDialog(
          content: SingleChildScrollView(
            child: ColorPicker(
              pickerColor: Colors.red,
              onColorChanged: (_) {},
              enableAlpha: false,
              hexInputBar: true,
              labelTypes: const [],
              pickerAreaHeightPercent: 0.7,
              displayThumbColor: true,
              portraitOnly: true,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(tester.takeException(), isNull);

    await tester.tap(find.byType(EditableText), warnIfMissed: false);
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('bottom navigation bar builds and responds', (tester) async {
    int? tapped;
    await tester.pumpWidget(
      _shell(
        body: const SizedBox(),
        bottomNavigationBar: AnimatedBottomNavigationBar.builder(
          itemCount: 3,
          tabBuilder: (index, isActive) => Text('tab $index'),
          activeIndex: 0,
          gapLocation: GapLocation.none,
          onTap: (index) => tapped = index,
        ),
      ),
    );
    await tester.pump();
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('tab 1'));
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(tapped, 1);
    await tester.pump(const Duration(seconds: 1));
  });
}
