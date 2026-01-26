import 'package:video_player_media_kit/video_player_media_kit.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:window_manager/window_manager.dart';

import 'dart:io' show Platform;

import '../services/custom_font_manager.dart';
import '../services/settings_cache.dart';
import '../screens/projects_page.dart';
import '../services/database_helper.dart';
import '../services/theme_provider.dart';
import '../services/log_service.dart';
import '../widgets/main_navigation.dart';
import '../theme/theme.dart';
import '../services/database_import_ffi.dart';
import '../utils/dir_utils.dart';
import '../utils/test_mode.dart' as test_config;
import 'constants/window_constants.dart';
import 'styles/styles.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await LogService.instance.initialize();
  await _main();
}

Future<void> _main() async {
  WidgetsBinding widgetsBinding = WidgetsFlutterBinding.ensureInitialized();
  initDatabase();

  // Clean up orphaned temp files from previous sessions
  await DirUtils.clearStabilizationTempFiles();

  VideoPlayerMediaKit.ensureInitialized(linux: true);

  if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
    await DB.instance.createTablesIfNotExist();
    // Initialize custom fonts after database is ready
    await CustomFontManager.instance.initialize();
    await windowManager.ensureInitialized();

    final List<Map<String, dynamic>> projects =
        await DB.instance.getAllProjects();
    final bool hasProjects = projects.isNotEmpty;

    final Size startSize =
        hasProjects ? kWindowSizeDefault : kWindowSizeWelcome;
    final Size minSize =
        hasProjects ? kWindowMinSizeDefault : kWindowMinSizeWelcome;

    final options = WindowOptions(
      size: startSize,
      minimumSize: minSize,
      center: true,
      title: 'AgeLapse v2.4.0',
    );

    await windowManager.waitUntilReadyToShow(options, () async {
      if (!test_config.isTestMode) {
        await windowManager.show();
        await windowManager.focus();
      }

      if (!hasProjects) {
        final currentSize = await windowManager.getSize();
        if (currentSize.height < kWindowMinSizeWelcome.height) {
          await windowManager.setSize(
            Size(currentSize.width, kWindowMinSizeWelcome.height),
          );
        }
      }
    });
  } else {
    FlutterNativeSplash.preserve(widgetsBinding: widgetsBinding);

    await _initializeApp();

    FlutterNativeSplash.remove();

    debugPaintSizeEnabled = false;

    // Note: SystemUiOverlayStyle is now set dynamically in MaterialApp.builder
  }

  runApp(AgeLapse(homePage: await _getHomePage()));
}

Future<void> _initializeApp() async {
  final futures = <Future>[DB.instance.createTablesIfNotExist()];

  // Skip notification initialization in test mode to avoid permission prompts
  if (!test_config.isTestMode) {
    futures.add(initializeNotifications());
  }

  await Future.wait(futures);

  // Initialize custom fonts after database is ready
  await CustomFontManager.instance.initialize();
}

Future<void> initializeNotifications() async {
  FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();

  const AndroidInitializationSettings initializationSettingsAndroid =
      AndroidInitializationSettings('@mipmap/ic_launcher');
  final DarwinInitializationSettings initializationSettingsDarwin =
      DarwinInitializationSettings();
  final InitializationSettings initializationSettings = InitializationSettings(
    android: initializationSettingsAndroid,
    iOS: initializationSettingsDarwin,
  );

  await flutterLocalNotificationsPlugin.initialize(
    initializationSettings,
    onDidReceiveNotificationResponse:
        (NotificationResponse notificationResponse) async {
      if (notificationResponse.payload != null) {
        // In the future, need to handle notification tapped logic here
      }
    },
  );
}

Future<Widget> _getHomePage() async {
  if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
    //return DesktopHomePage();
  }

  final String defaultProject = await DB.instance.getSettingValueByTitle(
    'default_project',
  );

  if (defaultProject != "none") {
    final int projectId = int.parse(defaultProject);
    SettingsCache settingsCache = await SettingsCache.initialize(projectId);
    return MainNavigation(
      projectId: projectId,
      showFlashingCircle: false,
      projectName: 'Default Project',
      initialSettingsCache: settingsCache,
    );
  }

  // If default is not set or not found, show projects page so the user can
  // either select or create a new project.
  return const ProjectsPage();
}

/// Loads theme mode from database with safe fallback
Future<String> _loadThemeMode() async {
  try {
    final value = await DB.instance.getSettingValueByTitle('theme', 'global');
    // Guard against invalid values
    if (value == 'light' || value == 'dark' || value == 'system') {
      return value;
    }
    return 'system'; // Default for new installs
  } catch (e) {
    return 'system';
  }
}

/// Updates system UI overlay style based on current theme
void _updateSystemUiOverlay(bool isLight) {
  if (Platform.isAndroid || Platform.isIOS) {
    SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle(
      systemNavigationBarColor:
          isLight ? const Color(0xFFFFFFFF) : const Color(0xFF000000),
      systemNavigationBarIconBrightness:
          isLight ? Brightness.dark : Brightness.light,
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: isLight ? Brightness.dark : Brightness.light,
    ));
  }
}

class AgeLapse extends StatelessWidget {
  final Widget homePage;

  const AgeLapse({super.key, required this.homePage});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String>(
      future: _loadThemeMode(),
      builder: (context, themeSnapshot) {
        if (themeSnapshot.connectionState == ConnectionState.done) {
          return _buildApp(context, homePage, themeSnapshot.data!);
        } else {
          return const MaterialApp(
            home: Scaffold(body: Center(child: CircularProgressIndicator())),
            debugShowCheckedModeBanner: false,
          );
        }
      },
    );
  }

  Widget _buildApp(BuildContext context, Widget homePage, String theme) {
    MaterialTheme materialTheme = const MaterialTheme(TextTheme());
    final bool isDesktop =
        Platform.isMacOS || Platform.isWindows || Platform.isLinux;

    final materialApp = ChangeNotifierProvider(
      create: (_) => ThemeProvider(theme, materialTheme),
      child: Consumer<ThemeProvider>(
        builder: (context, themeProvider, _) => MaterialApp(
          title: 'AgeLapse',
          theme: themeProvider.lightTheme,
          darkTheme: themeProvider.darkTheme,
          themeMode: themeProvider.flutterThemeMode,
          builder: (context, child) {
            // Sync static AppColors shim with current theme
            AppColors.syncFromContext(context);

            // Update system UI overlay based on current theme
            _updateSystemUiOverlay(themeProvider.isLightMode);

            return child!;
          },
          home: homePage,
          debugShowCheckedModeBanner: false,
        ),
      ),
    );

    if (!isDesktop) return materialApp;

    return PlatformMenuBar(
      menus: [
        PlatformMenu(
          label: 'AgeLapse',
          menus: [
            PlatformMenuItemGroup(
              members: [
                PlatformMenuItem(
                  label: 'About AgeLapse',
                  onSelected: null,
                ),
              ],
            ),
            PlatformMenuItemGroup(
              members: [
                PlatformMenuItem(
                  label: 'Hide AgeLapse',
                  shortcut: const SingleActivator(LogicalKeyboardKey.keyH,
                      meta: true),
                  onSelected: () => SystemNavigator.pop(),
                ),
                PlatformMenuItem(
                  label: 'Quit AgeLapse',
                  shortcut: const SingleActivator(LogicalKeyboardKey.keyQ,
                      meta: true),
                  onSelected: () => SystemNavigator.pop(),
                ),
              ],
            ),
          ],
        ),
        PlatformMenu(
          label: 'Edit',
          menus: [
            PlatformMenuItemGroup(
              members: [
                PlatformMenuItem(
                  label: 'Cut',
                  shortcut: const SingleActivator(LogicalKeyboardKey.keyX,
                      meta: true),
                  onSelected: () {},
                ),
                PlatformMenuItem(
                  label: 'Copy',
                  shortcut: const SingleActivator(LogicalKeyboardKey.keyC,
                      meta: true),
                  onSelected: () {},
                ),
                PlatformMenuItem(
                  label: 'Paste',
                  shortcut: const SingleActivator(LogicalKeyboardKey.keyV,
                      meta: true),
                  onSelected: () {},
                ),
                PlatformMenuItem(
                  label: 'Select All',
                  shortcut: const SingleActivator(LogicalKeyboardKey.keyA,
                      meta: true),
                  onSelected: () {},
                ),
              ],
            ),
          ],
        ),
        PlatformMenu(
          label: 'Help',
          menus: [
            PlatformMenuItem(
              label: 'Documentation',
              onSelected: () async {
                final uri = Uri.parse('https://agelapse.com/docs');
                await launchUrl(uri, mode: LaunchMode.externalApplication);
              },
            ),
          ],
        ),
      ],
      child: materialApp,
    );
  }
}
