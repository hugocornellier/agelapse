import 'package:flutter/material.dart';
import '../services/settings_cache.dart';
import '../styles/styles.dart';
import '../utils/settings_utils.dart';
import '../widgets/main_navigation.dart';
import '../widgets/settings_sheet.dart';

class SetUpNotificationsPage extends StatefulWidget {
  final int projectId;
  final String projectName;
  final Future<void> Function() stabCallback;
  final Future<void> Function() cancelStabCallback;
  final Future<void> Function() refreshSettings;
  final void Function() clearRawAndStabPhotos;
  final SettingsCache? settingsCache;

  const SetUpNotificationsPage({
    super.key,
    required this.projectId,
    required this.projectName,
    required this.stabCallback,
    required this.cancelStabCallback,
    required this.refreshSettings,
    required this.clearRawAndStabPhotos,
    required this.settingsCache,
  });

  @override
  SetUpNotificationsPageState createState() => SetUpNotificationsPageState();
}

class SetUpNotificationsPageState extends State<SetUpNotificationsPage> {
  final Color appBarColor = const Color(0xff151517);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(""),
        backgroundColor: appBarColor,
        actions: [
          IconButton(
            icon: const Icon(Icons.close),
            onPressed: () => close(),
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Container _buildBody() {
    return Container(
      color: appBarColor,
      child: _buildSetUpNotificationsPage(),
    );
  }

  Widget _buildSetUpNotificationsPage() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const SizedBox(height: 128),
            _buildNotificationImage(),
            const SizedBox(height: 64),
            const Text(
              "Notifications",
              style: TextStyle(fontSize: 24),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 40),
            const Text(
              "We will remind you at 5:00PM daily to take a photo. Configure this in Settings.",
              style: TextStyle(fontSize: 14.5),
              textAlign: TextAlign.center,
            ),
            Expanded(child: Container()),
            _buildActionButton("Configure Now", 1),
            const SizedBox(height: 10),
            _buildActionButton("Later", 2),
            const SizedBox(height: 64),
          ],
        ),
      ),
    );
  }

  Widget _buildNotificationImage() {
    const double imageDiameter = 100;
    const String imagePath = 'assets/images/notif.png';

    return ClipRect(
      child: Image.asset(
        imagePath,
        width: imageDiameter,
        height: imageDiameter,
        fit: BoxFit.cover,
      ),
    );
  }

  Widget _buildActionButton(String text, int index) {
    return FractionallySizedBox(
      widthFactor: 1.0,
      child: ElevatedButton(
        onPressed: () => index == 1 ? navigateToSettings() : close(),
        style: ElevatedButton.styleFrom(
          backgroundColor: text == "Later"
              ? Colors.grey.shade800
              : AppColors.darkerLightBlue,
          minimumSize: const Size(double.infinity, 50),
          padding: const EdgeInsets.symmetric(vertical: 18.0),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(6.0),
          ),
        ),
        child: Text(
          text.toUpperCase(),
          style: const TextStyle(
              fontSize: 15, color: Colors.white, fontWeight: FontWeight.bold),
        ),
      ),
    );
  }

  void navigateToSettings() {
    SettingsUtil.setHasOpenedNotifPageToTrue(widget.projectId.toString());

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        return SettingsSheet(
          projectId: widget.projectId,
          cancelStabCallback: widget.cancelStabCallback,
          stabCallback: widget.stabCallback,
          onlyShowNotificationSettings: true,
          refreshSettings: widget.refreshSettings,
          clearRawAndStabPhotos: widget.clearRawAndStabPhotos,
        );
      },
    );
  }

  void close() {
    SettingsUtil.setHasOpenedNotifPageToTrue(widget.projectId.toString());

    Navigator.pushReplacement(
      context,
      PageRouteBuilder(
        pageBuilder: (context, animation1, animation2) => MainNavigation(
          projectId: widget.projectId,
          projectName: widget.projectName,
          index: 0,
          showFlashingCircle: false,
        ),
        transitionDuration: Duration.zero,
        reverseTransitionDuration: Duration.zero,
      ),
    );
  }
}
