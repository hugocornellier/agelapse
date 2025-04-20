import 'package:AgeLapse/services/settings_cache.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:provider/provider.dart';
import 'dart:io' show Platform;
import '../screens/projects_page.dart';
import '../services/database_helper.dart';
import '../services/theme_provider.dart';
import '../widgets/main_navigation.dart';
import '../theme/theme.dart';

void main() async {
  if (!Platform.isWindows && !Platform.isLinux && !Platform.isMacOS) {
    WidgetsBinding widgetsBinding = WidgetsFlutterBinding.ensureInitialized();
    FlutterNativeSplash.preserve(widgetsBinding: widgetsBinding);

    await _initializeApp();

    FlutterNativeSplash.remove();

    debugPaintSizeEnabled = false;

    SystemUiOverlayStyle style = const SystemUiOverlayStyle(
      systemNavigationBarColor: Colors.black,
      systemNavigationBarIconBrightness: Brightness.light,
    );
    SystemChrome.setSystemUIOverlayStyle(style);
  } else {
    WidgetsBinding widgetsBinding = WidgetsFlutterBinding.ensureInitialized();

    await DB.instance.createTablesIfNotExist();

    Map<String, dynamic>? project = await DB.instance.getProject(1);
    if (project == null) {
      final int projectId = await DB.instance.addProject(
        "Untitled",
        "face",
        DateTime.now().millisecondsSinceEpoch
      );
    }
  }

  runApp(AgeLapse(homePage: await _getHomePage()));
}

Future<void> _initializeApp() async {
  await Future.wait([
    DB.instance.createTablesIfNotExist(),
    initializeNotifications(),
  ]);
}

Future<void> initializeNotifications() async {
  FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();

  const AndroidInitializationSettings initializationSettingsAndroid = AndroidInitializationSettings('@mipmap/ic_launcher');
  final DarwinInitializationSettings initializationSettingsDarwin = DarwinInitializationSettings();
  final InitializationSettings initializationSettings = InitializationSettings(
    android: initializationSettingsAndroid,
    iOS: initializationSettingsDarwin,
  );

  await flutterLocalNotificationsPlugin.initialize(
    initializationSettings,
    onDidReceiveNotificationResponse: (NotificationResponse notificationResponse) async {
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

  final String defaultProject = await DB.instance.getSettingValueByTitle('default_project');

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

class AgeLapse extends StatelessWidget {
  final Widget homePage;

  const AgeLapse({super.key, required this.homePage});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String>(
      future: _fetchTheme(),
      builder: (context, themeSnapshot) {
        if (themeSnapshot.connectionState == ConnectionState.done) {
          return _buildApp(context, homePage, themeSnapshot.data!);
        } else {
          return const MaterialApp(
              home: Scaffold(body: Center(child: CircularProgressIndicator())),
              debugShowCheckedModeBanner: false
          );
        }
      },
    );
  }

  Future<String> _fetchTheme() async {
    var data = await DB.instance.getSettingByTitle('theme');
    return data?['value'] ?? 'system';
  }

  Widget _buildApp(BuildContext context, Widget homePage, String theme) {
    MaterialTheme materialTheme = const MaterialTheme(TextTheme()); 
    return ChangeNotifierProvider(
      create: (_) => ThemeProvider(theme, materialTheme),
      child: Consumer<ThemeProvider>(
        builder: (context, themeProvider, _) => MaterialApp(
            title: 'AgeLapse',
            theme: themeProvider.themeData,
            home: homePage,
            debugShowCheckedModeBanner: false
        ),
      ),
    );
  }
}
