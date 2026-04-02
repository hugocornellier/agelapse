import 'package:flutter/foundation.dart';

/// Lightweight service for pages to register additional menu bar items.
/// Pages register callbacks on mount and unregister on dispose.
/// The PlatformMenuBar in main.dart listens and rebuilds accordingly.
class MenuBarService extends ChangeNotifier {
  static final MenuBarService instance = MenuBarService._();
  MenuBarService._();

  VoidCallback? _onZoomIn;
  VoidCallback? _onZoomOut;
  VoidCallback? _onResetZoom;

  VoidCallback? get onZoomIn => _onZoomIn;
  VoidCallback? get onZoomOut => _onZoomOut;
  VoidCallback? get onResetZoom => _onResetZoom;

  bool get hasToolsMenu => _onZoomIn != null || _onZoomOut != null;

  void registerToolsMenu({
    VoidCallback? onZoomIn,
    VoidCallback? onZoomOut,
    VoidCallback? onResetZoom,
  }) {
    _onZoomIn = onZoomIn;
    _onZoomOut = onZoomOut;
    _onResetZoom = onResetZoom;
    notifyListeners();
  }

  void unregisterToolsMenu() {
    _onZoomIn = null;
    _onZoomOut = null;
    _onResetZoom = null;
    notifyListeners();
  }
}
