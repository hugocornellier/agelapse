# AgeLapse patch

This directory is a minimal vendoring of `animated_bottom_navigation_bar` 1.4.1 from pub.dev
(archive SHA-256
`7ad064b98536d9a38366d3f39907a82da35c695ed79b9ed27ccd16444f5c3184`).
Examples and upstream tests are omitted because this copy is used only as a
dependency.

AgeLapse makes two changes:

- `package:flutter/material.dart` and `package:flutter/cupertino.dart` imports
  in `lib/` become `package:material_ui/material_ui.dart` and
  `package:cupertino_ui/cupertino_ui.dart`.
- `pubspec.yaml` depends on the packages those imports need.

Its bar calls `Scaffold.geometryOf`, which throws unless the Scaffold above it comes from the same Material library as the bar. The app's Scaffolds and dialogs now come from `material_ui`, and
`MaterialUiCompatibilityBridge` only forwards the theme and localizations, so
upstream cannot be used until it migrates. Delete this directory and its
`dependency_overrides` entry once a pub.dev release has.
