// Copyright 2019 The FlutterCandies author. All rights reserved.
// Use of this source code is governed by an Apache license that can be found
// in the LICENSE file.

import 'package:flutter/material.dart';

/// Auto-scaling text between [minScaleFactor] and [maxScaleFactor].
final class ScaleText extends StatelessWidget {
  const ScaleText(
    String this.text, {
    super.key,
    this.style,
    this.strutStyle,
    this.maxLines,
    this.overflow,
    this.textAlign,
    this.textDirection,
    this.semanticsLabel,
    this.softWrap,
    this.minScaleFactor = 0.7,
    this.maxScaleFactor = 1.3,
  }) : textSpans = null;

  const ScaleText.rich(
    List<TextSpan> this.textSpans, {
    super.key,
    this.style,
    this.strutStyle,
    this.maxLines,
    this.overflow,
    this.textAlign,
    this.textDirection,
    this.semanticsLabel,
    this.softWrap,
    this.minScaleFactor = 0.7,
    this.maxScaleFactor = 1.3,
  }) : text = null;

  final String? text;
  final List<TextSpan>? textSpans;

  final TextStyle? style;
  final StrutStyle? strutStyle;
  final int? maxLines;
  final TextOverflow? overflow;
  final TextAlign? textAlign;
  final TextDirection? textDirection;
  final String? semanticsLabel;
  final bool? softWrap;

  final double minScaleFactor;
  final double maxScaleFactor;

  @override
  Widget build(BuildContext context) {
    final MediaQueryData mqd = MediaQuery.of(context);
    final effectiveScaler = mqd.textScaler.clamp(
      minScaleFactor: minScaleFactor,
      maxScaleFactor: maxScaleFactor,
    );
    return MediaQuery(
      data: mqd.copyWith(textScaler: effectiveScaler),
      child: Text.rich(
        TextSpan(text: text, children: textSpans),
        style: style,
        strutStyle: strutStyle,
        maxLines: maxLines,
        textAlign: textAlign,
        overflow: overflow,
        textDirection: textDirection,
        semanticsLabel: semanticsLabel,
        softWrap: softWrap,
      ),
    );
  }
}
