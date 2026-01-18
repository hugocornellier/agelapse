import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:agelapse/widgets/setting_list_tile.dart';

/// Widget tests for SettingListTile.
void main() {
  group('SettingListTile Widget', () {
    test('SettingListTile can be instantiated', () {
      expect(SettingListTile, isNotNull);
    });

    test('SettingListTile stores required parameters', () {
      final widget = SettingListTile(
        title: 'Test Setting',
        infoContent: 'Info about the setting',
        contentWidget: const Text('Content'),
        showInfo: true,
      );

      expect(widget.title, 'Test Setting');
      expect(widget.infoContent, 'Info about the setting');
      expect(widget.showInfo, isTrue);
    });

    test('infoContent can be null', () {
      final widget = SettingListTile(
        title: 'Test',
        infoContent: null,
        contentWidget: const Text('Content'),
        showInfo: false,
      );

      expect(widget.infoContent, isNull);
    });

    test('showInfo can be null', () {
      final widget = SettingListTile(
        title: 'Test',
        infoContent: 'Info',
        contentWidget: const Text('Content'),
        showInfo: null,
      );

      expect(widget.showInfo, isNull);
    });

    test('disabled defaults to null', () {
      final widget = SettingListTile(
        title: 'Test',
        infoContent: 'Info',
        contentWidget: const Text('Content'),
        showInfo: false,
      );

      expect(widget.disabled, isNull);
    });

    test('disabled can be set', () {
      final widget = SettingListTile(
        title: 'Test',
        infoContent: 'Info',
        contentWidget: const Text('Content'),
        showInfo: false,
        disabled: true,
      );

      expect(widget.disabled, isTrue);
    });

    test('showDivider defaults to null', () {
      final widget = SettingListTile(
        title: 'Test',
        infoContent: 'Info',
        contentWidget: const Text('Content'),
        showInfo: false,
      );

      expect(widget.showDivider, isNull);
    });

    test('showDivider can be set', () {
      final widget = SettingListTile(
        title: 'Test',
        infoContent: 'Info',
        contentWidget: const Text('Content'),
        showInfo: false,
        showDivider: true,
      );

      expect(widget.showDivider, isTrue);
    });
  });

  group('SettingListTile Widget Rendering', () {
    testWidgets('renders title', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SettingListTile(
              title: 'My Setting Title',
              infoContent: 'Info',
              contentWidget: Text('Content'),
              showInfo: false,
            ),
          ),
        ),
      );

      expect(find.text('My Setting Title'), findsOneWidget);
    });

    testWidgets('renders content widget', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SettingListTile(
              title: 'Title',
              infoContent: 'Info',
              contentWidget: Text('My Content Widget'),
              showInfo: false,
            ),
          ),
        ),
      );

      expect(find.text('My Content Widget'), findsOneWidget);
    });

    testWidgets('shows info icon when showInfo is true', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SettingListTile(
              title: 'Title',
              infoContent: 'Info content here',
              contentWidget: Text('Content'),
              showInfo: true,
            ),
          ),
        ),
      );

      expect(find.byIcon(Icons.info_outline_rounded), findsOneWidget);
    });

    testWidgets('hides info icon when showInfo is false', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SettingListTile(
              title: 'Title',
              infoContent: 'Info',
              contentWidget: Text('Content'),
              showInfo: false,
            ),
          ),
        ),
      );

      expect(find.byIcon(Icons.info_outline_rounded), findsNothing);
    });

    testWidgets('shows divider when showDivider is true', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SettingListTile(
              title: 'Title',
              infoContent: 'Info',
              contentWidget: Text('Content'),
              showInfo: false,
              showDivider: true,
            ),
          ),
        ),
      );

      expect(find.byType(Divider), findsOneWidget);
    });

    testWidgets('hides divider when showDivider is false', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SettingListTile(
              title: 'Title',
              infoContent: 'Info',
              contentWidget: Text('Content'),
              showInfo: false,
              showDivider: false,
            ),
          ),
        ),
      );

      expect(find.byType(Divider), findsNothing);
    });

    testWidgets('info icon shows dialog when tapped', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SettingListTile(
              title: 'Title',
              infoContent: 'This is detailed info',
              contentWidget: Text('Content'),
              showInfo: true,
            ),
          ),
        ),
      );

      await tester.tap(find.byIcon(Icons.info_outline_rounded));
      await tester.pumpAndSettle();

      // AlertDialog should appear with info content
      expect(find.text('This is detailed info'), findsOneWidget);
      expect(find.text('Got it'), findsOneWidget);
    });

    testWidgets('info dialog can be dismissed', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SettingListTile(
              title: 'Title',
              infoContent: 'Info text',
              contentWidget: Text('Content'),
              showInfo: true,
            ),
          ),
        ),
      );

      await tester.tap(find.byIcon(Icons.info_outline_rounded));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Got it'));
      await tester.pumpAndSettle();

      // Dialog should be dismissed
      expect(find.text('Info text'), findsNothing);
    });
  });

  group('SettingListTile Content Widgets', () {
    testWidgets('works with Switch as content', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SettingListTile(
              title: 'Toggle Setting',
              infoContent: 'Toggle info',
              contentWidget: Switch(value: true, onChanged: (_) {}),
              showInfo: false,
            ),
          ),
        ),
      );

      expect(find.byType(Switch), findsOneWidget);
    });

    testWidgets('works with DropdownButton as content', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SettingListTile(
              title: 'Dropdown Setting',
              infoContent: 'Dropdown info',
              contentWidget: DropdownButton<String>(
                value: 'Option 1',
                items: const [
                  DropdownMenuItem(value: 'Option 1', child: Text('Option 1')),
                ],
                onChanged: (_) {},
              ),
              showInfo: false,
            ),
          ),
        ),
      );

      expect(find.byType(DropdownButton<String>), findsOneWidget);
    });
  });
}
