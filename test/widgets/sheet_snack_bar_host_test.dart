import 'package:agelapse/widgets/sheet_snack_bar_host.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Stands in for the settings sheet: a panel with a button that shows a
/// SnackBar with an action through `ScaffoldMessenger.of(context)`, the way
/// the reminder toggle does when notifications are blocked.
class _Sheet extends StatelessWidget {
  const _Sheet({required this.onAction});

  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: _sheetContentHeight,
      color: Colors.grey,
      alignment: Alignment.center,
      child: ElevatedButton(
        onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Notifications are turned off'),
            action: SnackBarAction(label: 'Open settings', onPressed: onAction),
          ),
        ),
        child: const Text('Turn on'),
      ),
    );
  }
}

const double _hostHeight = 400;
const double _sheetContentHeight = 300;

Future<void> _openSheet(
  WidgetTester tester, {
  required bool withHost,
  required VoidCallback onAction,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => Align(
            alignment: Alignment.topCenter,
            child: TextButton(
              onPressed: () => showModalBottomSheet<void>(
                context: context,
                isScrollControlled: true,
                builder: (_) => withHost
                    ? SheetSnackBarHost(
                        height: _hostHeight,
                        child: _Sheet(onAction: onAction),
                      )
                    : _Sheet(onAction: onAction),
              ),
              child: const Text('Open sheet'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open sheet'));
  await tester.pumpAndSettle();
}

void main() {
  group('SheetSnackBarHost', () {
    testWidgets('shows the SnackBar on the sheet, with a working action', (
      tester,
    ) async {
      var opened = 0;
      await _openSheet(tester, withHost: true, onAction: () => opened++);
      await tester.tap(find.text('Turn on'));
      await tester.pumpAndSettle();

      expect(
        find.descendant(
          of: find.byType(BottomSheet),
          matching: find.byType(SnackBar),
        ),
        findsOneWidget,
      );
      await tester.tap(find.text('Open settings'));
      await tester.pumpAndSettle();
      expect(opened, 1);
    });

    testWidgets('keeps the sheet at the given height, content at the bottom', (
      tester,
    ) async {
      await _openSheet(tester, withHost: true, onAction: () {});

      final screen = tester.getSize(find.byType(MaterialApp));
      expect(tester.getSize(find.byType(BottomSheet)).height, _hostHeight);
      expect(tester.getBottomLeft(find.byType(_Sheet)).dy, screen.height);
    });

    testWidgets('a tap above the sheet still closes it', (tester) async {
      await _openSheet(tester, withHost: true, onAction: () {});
      expect(find.byType(BottomSheet), findsOneWidget);

      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();
      expect(find.byType(BottomSheet), findsNothing);
    });

    testWidgets(
      'control: without the host the SnackBar hides under the sheet',
      (tester) async {
        var opened = 0;
        await _openSheet(tester, withHost: false, onAction: () => opened++);
        await tester.tap(find.text('Turn on'));
        await tester.pumpAndSettle();

        expect(find.byType(SnackBar), findsOneWidget);
        expect(
          find.descendant(
            of: find.byType(BottomSheet),
            matching: find.byType(SnackBar),
          ),
          findsNothing,
        );
        // The sheet covers the SnackBar, so the tap lands on the sheet.
        await tester.tap(find.text('Open settings'), warnIfMissed: false);
        await tester.pumpAndSettle();
        expect(opened, 0);
      },
    );
  });
}
