// Transform Tool - Pixelmator-style image transform widget
//
// Provides drag, resize, and rotate functionality with intuitive
// handle-based interactions.
//
// Usage:
//   TransformTool(
//     imageBytes: imageData,
//     canvasSize: Size(800, 600),
//     imageSize: Size(1920, 1080),
//     baseScale: 0.5,
//     onChanged: (state) => print('Transform: $state'),
//     onChangeEnd: (state) => saveToDatabase(state),
//   )

export 'transform_controller.dart';
export 'transform_gesture_handler.dart';
export 'transform_handle.dart';
export 'transform_handle_painter.dart';
export 'transform_state.dart';
export 'transform_tool.dart';
