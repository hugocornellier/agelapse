import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:agelapse/styles/styles.dart';

void main() {
  group('overlayButtonRoundStyle', () {
    test('returns ElevatedButton style with CircleBorder', () {
      final style = overlayButtonRoundStyle();
      expect(style, isA<ButtonStyle>());
      expect(style.shape?.resolve({}), isA<CircleBorder>());
    });

    test('has correct background color', () {
      final style = overlayButtonRoundStyle();
      final bgColor = style.backgroundColor?.resolve({});
      expect(bgColor, equals(AppColors.darkOverlay));
    });

    test('has white foreground color', () {
      final style = overlayButtonRoundStyle();
      final fgColor = style.foregroundColor?.resolve({});
      expect(fgColor, equals(Colors.white));
    });

    test('has padding of 18', () {
      final style = overlayButtonRoundStyle();
      final padding = style.padding?.resolve({});
      expect(padding, equals(const EdgeInsets.all(18)));
    });
  });

  group('takePhotoRoundStyle', () {
    test('returns ElevatedButton style with CircleBorder', () {
      final style = takePhotoRoundStyle();
      expect(style, isA<ButtonStyle>());
      expect(style.shape?.resolve({}), isA<CircleBorder>());
    });

    test('has correct background color', () {
      final style = takePhotoRoundStyle();
      final bgColor = style.backgroundColor?.resolve({});
      expect(bgColor, equals(AppColors.darkOverlay));
    });

    test('has white foreground color', () {
      final style = takePhotoRoundStyle();
      final fgColor = style.foregroundColor?.resolve({});
      expect(fgColor, equals(Colors.white));
    });

    test('has padding of 3', () {
      final style = takePhotoRoundStyle();
      final padding = style.padding?.resolve({});
      expect(padding, equals(const EdgeInsets.all(3)));
    });

    test('has zero minimum size', () {
      final style = takePhotoRoundStyle();
      final minSize = style.minimumSize?.resolve({});
      expect(minSize, equals(Size.zero));
    });
  });

  group('AppColors', () {
    test('darkOverlay has correct color with alpha', () {
      expect(AppColors.darkOverlay, isA<Color>());
      // Base color is 0xFF232121 with 0.5 alpha
      // Color values are 0-1 range: 0x23=35, 35/255=0.137
      expect(AppColors.darkOverlay.a, closeTo(0.5, 0.01));
    });

    test('lightGrey is correct', () {
      expect(AppColors.lightGrey, equals(const Color(0xFF8E8E93)));
    });

    test('lightBlue is correct', () {
      expect(AppColors.lightBlue, equals(const Color(0xFF40C4FF)));
    });

    test('darkerLightBlue is correct', () {
      expect(AppColors.darkerLightBlue, equals(const Color(0xff3285af)));
    });

    test('evenDarkerLightBlue is correct', () {
      expect(AppColors.evenDarkerLightBlue, equals(const Color(0xff206588)));
    });

    test('orange is correct', () {
      expect(AppColors.orange, equals(const Color(0xffc9a179)));
    });

    test('darkGrey is correct', () {
      expect(AppColors.darkGrey, equals(const Color(0xff0F0F0F)));
    });

    test('lessDarkGrey is correct', () {
      expect(AppColors.lessDarkGrey, equals(const Color(0xFF2A2A2A)));
    });

    test('settingsBackground is correct', () {
      expect(AppColors.settingsBackground, equals(const Color(0xff0A0A0A)));
    });

    test('settingsCardBackground is correct', () {
      expect(AppColors.settingsCardBackground, equals(const Color(0xff1A1A1A)));
    });

    test('settingsCardBorder is correct', () {
      expect(AppColors.settingsCardBorder, equals(const Color(0xff2A2A2A)));
    });

    test('settingsDivider is correct', () {
      expect(AppColors.settingsDivider, equals(const Color(0xff2A2A2A)));
    });

    test('settingsAccent is correct', () {
      expect(AppColors.settingsAccent, equals(const Color(0xff4A9ECC)));
    });

    test('settingsTextPrimary is correct', () {
      expect(AppColors.settingsTextPrimary, equals(const Color(0xffFFFFFF)));
    });

    test('settingsTextSecondary is correct', () {
      expect(AppColors.settingsTextSecondary, equals(const Color(0xff8E8E93)));
    });

    test('settingsTextTertiary is correct', () {
      expect(AppColors.settingsTextTertiary, equals(const Color(0xff636366)));
    });

    test('settingsInputBackground is correct', () {
      expect(
          AppColors.settingsInputBackground, equals(const Color(0xff1A1A1A)));
    });
  });
}
