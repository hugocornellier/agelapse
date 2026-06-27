import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:agelapse/models/detected_faces_snapshot.dart';
import 'package:agelapse/models/face_detection_cache_result.dart';
import 'package:agelapse/widgets/detected_faces_chip.dart';

DetectedFacesSnapshot _available(int n) => DetectedFacesSnapshot(
      timestamp: 't',
      projectId: 1,
      projectType: 'face',
      rawPath: '/x',
      availability: DetectedFacesAvailability.available,
      cache: FaceDetectionCacheResult(
        orientation: 'original',
        faces: List.generate(
          n,
          (i) => const CachedFace(boundingBox: Rect.fromLTRB(0, 0, 10, 10)),
        ),
        selectedFaceIndex: 0,
      ),
    );

DetectedFacesSnapshot _state(DetectedFacesAvailability a) =>
    DetectedFacesSnapshot(
      timestamp: 't',
      projectId: 1,
      projectType: 'face',
      rawPath: '/x',
      availability: a,
    );

Future<void> _pump(
  WidgetTester tester,
  Future<DetectedFacesSnapshot>? future, {
  VoidCallback? onTap,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: DetectedFacesChip(future: future, onTap: onTap),
      ),
    ),
  );
}

void main() {
  testWidgets('shows count and is tappable when faces are available',
      (tester) async {
    var tapped = 0;
    await _pump(tester, Future.value(_available(3)), onTap: () => tapped++);
    await tester.pumpAndSettle();

    expect(find.text('3'), findsOneWidget);
    await tester.tap(find.text('3'));
    expect(tapped, 1);
  });

  testWidgets('shows 0 for no faces and is not tappable', (tester) async {
    var tapped = 0;
    await _pump(
      tester,
      Future.value(_state(DetectedFacesAvailability.noFaces)),
      onTap: () => tapped++,
    );
    await tester.pumpAndSettle();

    expect(find.text('0'), findsOneWidget);
    await tester.tap(find.text('0'));
    expect(tapped, 0);
  });

  testWidgets('hides entirely when count is unknown (legacy)', (tester) async {
    await _pump(
      tester,
      Future.value(_state(DetectedFacesAvailability.legacyCacheMissing)),
    );
    await tester.pumpAndSettle();

    expect(find.byType(Text), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('renders nothing when future is null', (tester) async {
    await _pump(tester, null);
    await tester.pumpAndSettle();
    expect(find.byType(Text), findsNothing);
  });

  testWidgets('shows a spinner while loading', (tester) async {
    final completer = Completer<DetectedFacesSnapshot>();
    await _pump(tester, completer.future);
    await tester.pump(); // let FutureBuilder build the waiting state

    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    completer.complete(_available(1));
    await tester.pumpAndSettle();
  });
}
