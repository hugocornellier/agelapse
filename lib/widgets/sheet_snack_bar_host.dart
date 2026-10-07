import 'package:flutter/material.dart';

/// Gives a modal bottom sheet its own place to show SnackBars.
///
/// A widget inside a modal bottom sheet that calls
/// `ScaffoldMessenger.of(context).showSnackBar` otherwise reaches the app's
/// root messenger, which shows the SnackBar on the page under the sheet. The
/// sheet covers it, so the message and its action stay out of reach until the
/// sheet closes. Wrapping the sheet's widget in this one, where the sheet is
/// opened, puts a messenger and a transparent Scaffold between the two, so
/// the SnackBar appears at the bottom of the sheet, on top of it.
///
/// The Scaffold fills whatever height it is given, so [height] must be the
/// sheet's own height or the sheet grows to it. [child] is aligned to the
/// bottom, where a shorter sheet would sit anyway.
class SheetSnackBarHost extends StatelessWidget {
  const SheetSnackBarHost({
    super.key,
    required this.height,
    required this.child,
  });

  /// Height of the sheet, which the Scaffold fills.
  final double height;

  /// The sheet. SnackBars it shows through `ScaffoldMessenger.of(context)`
  /// land on this host.
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      child: ScaffoldMessenger(
        child: Scaffold(
          backgroundColor: Colors.transparent,
          // The sheet did not move for the keyboard before it had a Scaffold.
          resizeToAvoidBottomInset: false,
          body: Align(alignment: Alignment.bottomCenter, child: child),
        ),
      ),
    );
  }
}
