import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:agelapse/screens/tips_page.dart';

/// Widget tests for TipsPage.
void main() {
  group('TipsPage Widget', () {
    test('TipsPage can be instantiated', () {
      expect(TipsPage, isNotNull);
    });

    test('TipsPage stores required parameters', () {
      final widget = TipsPage(
        projectId: 1,
        projectName: 'Test Project',
        goToPage: (index) {},
      );

      expect(widget.projectId, 1);
      expect(widget.projectName, 'Test Project');
    });

    test('goToPage callback is stored correctly', () {
      int? receivedIndex;

      final widget = TipsPage(
        projectId: 1,
        projectName: 'Test',
        goToPage: (index) {
          receivedIndex = index;
        },
      );

      widget.goToPage(2);
      expect(receivedIndex, 2);
    });

    test('TipsPage creates state', () {
      final widget = TipsPage(
        projectId: 1,
        projectName: 'Test',
        goToPage: (index) {},
      );

      expect(widget.createState(), isA<TipsPageState>());
    });
  });

  group('CustomWidget', () {
    test('CustomWidget can be instantiated with icon', () {
      const widget = CustomWidget(
        title: 'Test Title',
        description: 'Test Description',
        icon: Icons.tips_and_updates,
      );

      expect(widget.title, 'Test Title');
      expect(widget.description, 'Test Description');
      expect(widget.icon, Icons.tips_and_updates);
      expect(widget.svgIcon, isNull);
    });

    test('CustomWidget with icon is a StatelessWidget', () {
      const widget = CustomWidget(
        title: 'Title',
        description: 'Description',
        icon: Icons.balance,
      );

      expect(widget, isA<StatelessWidget>());
    });
  });
}
