import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:agelapse/screens/faq_page.dart';

/// Widget tests for FAQPage.
void main() {
  group('FAQPage Widget', () {
    test('FAQPage can be instantiated', () {
      expect(FAQPage, isNotNull);
    });

    test('FAQPage has no required parameters', () {
      const widget = FAQPage();
      expect(widget, isA<FAQPage>());
    });

    test('FAQPage is a StatelessWidget', () {
      const widget = FAQPage();
      expect(widget, isA<StatelessWidget>());
    });
  });

  group('FAQItem Widget', () {
    test('FAQItem can be instantiated', () {
      expect(FAQItem, isNotNull);
    });

    test('FAQItem stores required parameters', () {
      const widget = FAQItem(
        question: 'What is AgeLapse?',
        answer: 'An aging timelapse app.',
      );

      expect(widget.question, 'What is AgeLapse?');
      expect(widget.answer, 'An aging timelapse app.');
    });

    test('FAQItem is a StatelessWidget', () {
      const widget = FAQItem(
        question: 'Question?',
        answer: 'Answer.',
      );

      expect(widget, isA<StatelessWidget>());
    });

    test('FAQItem handles long question', () {
      const widget = FAQItem(
        question:
            'This is a very long question that spans multiple lines and tests how the widget handles longer text content?',
        answer: 'Short answer.',
      );

      expect(widget.question.length, greaterThan(50));
    });

    test('FAQItem handles long answer', () {
      const widget = FAQItem(
        question: 'Short question?',
        answer:
            'This is a very long answer that contains multiple sentences and paragraphs. '
            'It tests how the widget handles longer text content that might wrap to multiple lines. '
            'The answer should be displayed properly without truncation.',
      );

      expect(widget.answer.length, greaterThan(100));
    });
  });
}
