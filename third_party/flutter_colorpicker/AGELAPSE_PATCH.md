# AgeLapse patch

This directory is a minimal vendoring of `flutter_colorpicker` 1.1.0 from pub.dev
(archive SHA-256
`969de5f6f9e2a570ac660fb7b501551451ea2a1ab9e2097e89475f60e07816ea`).
Examples and upstream tests are omitted because this copy is used only as a
dependency.

AgeLapse makes two changes:

- `package:flutter/material.dart` and `package:flutter/cupertino.dart` imports
  in `lib/` become `package:material_ui/material_ui.dart` and
  `package:cupertino_ui/cupertino_ui.dart`.
- `pubspec.yaml` depends on the packages those imports need.

Its hex input is a `TextField`, which throws `No Material widget found` unless the Material above it comes from the same Material library. The app's Scaffolds and dialogs now come from `material_ui`, and
`MaterialUiCompatibilityBridge` only forwards the theme and localizations, so
upstream cannot be used until it migrates. Delete this directory and its
`dependency_overrides` entry once a pub.dev release has.
