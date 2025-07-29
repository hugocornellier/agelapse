// Copyright 2019 The FlutterCandies author. All rights reserved.
// Use of this source code is governed by an Apache license that can be found
// in the LICENSE file.

import 'package:flutter/material.dart';

/// Bind double [Tween] into animation the builder.
final class TweenAnimationBuilder2<A, B> extends StatelessWidget {
  const TweenAnimationBuilder2({
    super.key,
    required this.firstTween,
    required this.secondTween,
    required this.builder,
    this.firstTweenDuration = kThemeAnimationDuration,
    this.secondTweenDuration = kThemeAnimationDuration,
    this.firstTweenCurve = Curves.linear,
    this.secondTweenCurve = Curves.linear,
  });

  final Tween<A> firstTween;
  final Tween<B> secondTween;
  final Duration firstTweenDuration;
  final Duration secondTweenDuration;
  final Curve firstTweenCurve;
  final Curve secondTweenCurve;
  final Widget Function(BuildContext, A, B) builder;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<A>(
      tween: firstTween,
      curve: firstTweenCurve,
      duration: firstTweenDuration,
      builder: (__, A first, _) => TweenAnimationBuilder<B>(
        tween: secondTween,
        curve: secondTweenCurve,
        duration: secondTweenDuration,
        builder: (_, B second, __) => builder(context, first, second),
      ),
    );
  }
}
