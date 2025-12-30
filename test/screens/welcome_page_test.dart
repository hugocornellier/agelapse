import 'package:flutter_test/flutter_test.dart';
import 'package:agelapse/screens/welcome_page.dart';

/// Widget tests for WelcomePagePartTwo.
void main() {
  group('WelcomePagePartTwo Widget', () {
    test('WelcomePagePartTwo can be instantiated', () {
      expect(WelcomePagePartTwo, isNotNull);
    });

    test('WelcomePagePartTwo has no required parameters', () {
      const widget = WelcomePagePartTwo();
      expect(widget, isA<WelcomePagePartTwo>());
    });

    test('WelcomePagePartTwo creates state', () {
      const widget = WelcomePagePartTwo();
      expect(widget.createState(), isA<WelcomePagePartTwoState>());
    });
  });
}
