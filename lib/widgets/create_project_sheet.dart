import 'dart:io';
import '../screens/project_page.dart';
import 'package:flutter/material.dart';
import '../services/database_helper.dart';
import '../services/log_service.dart';
import '../styles/styles.dart';
import '../utils/notification_util.dart';
import 'main_navigation.dart';

class CreateProjectSheet extends StatefulWidget {
  final bool isDefaultProject;
  final bool showCloseButton;

  const CreateProjectSheet({
    super.key,
    required this.isDefaultProject,
    this.showCloseButton = true,
  });

  @override
  CreateProjectSheetState createState() => CreateProjectSheetState();
}

class CreateProjectSheetState extends State<CreateProjectSheet> {
  final TextEditingController _nameController = TextEditingController();
  String _selectedImage = 'assets/images/face.png';

  static Future<String?> checkForStabilizedImage(String dirPath) async {
    final directory = Directory(dirPath);
    if (await directory.exists()) {
      try {
        final pngFiles = await directory
            .list()
            .where((item) => item.path.endsWith('.png') && item is File)
            .toList();
        if (pngFiles.isNotEmpty) {
          return pngFiles.first.path;
        }
      } catch (e) {
        return null;
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16.0),
      height: 500,
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.85,
      ),
      decoration: const BoxDecoration(
        color: Color(0xff121212),
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(16.0),
          topRight: Radius.circular(16.0),
        ),
      ),
      child: Stack(
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 70.0),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.only(bottom: 16.0),
                    child: Text('Pose', style: TextStyle(color: Colors.grey)),
                  ),
                  _buildImageSelector(),
                  const SizedBox(height: 16),
                  const Padding(
                    padding: EdgeInsets.only(top: 16.0, bottom: 0.0),
                    child: Text('Name', style: TextStyle(color: Colors.grey)),
                  ),
                  _buildTextField(),
                  _buildActionButton()
                ],
              ),
            ),
          ),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Container(
              color: const Color(0xff121212),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Row(
                        children: [
                          Text('Create New Project',
                              style: TextStyle(
                                  fontSize: 22,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white)),
                        ],
                      ),
                      if (widget.showCloseButton)
                        IconButton(
                          icon: const Icon(Icons.close, color: Colors.white),
                          onPressed: () {
                            Navigator.of(context).pop();
                          },
                        ),
                    ],
                  ),
                  const Divider(),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildImageSelector() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceAround,
      children: [
        GestureDetector(
          onTap: () {
            setState(() {
              _selectedImage = 'assets/images/face.png';
            });
          },
          child: Image.asset(
            'assets/images/face.png', // proj type = face
            width: 100,
            height: 100,
            color:
                _selectedImage == 'assets/images/face.png' ? Colors.blue : null,
          ),
        ),
        GestureDetector(
          onTap: () {
            setState(() {
              _selectedImage = 'assets/images/musc.png';
            });
          },
          child: Image.asset(
            'assets/images/musc.png', // proj type = body
            width: 100,
            height: 100,
            color:
                _selectedImage == 'assets/images/musc.png' ? Colors.blue : null,
          ),
        ),
        GestureDetector(
          onTap: () {
            setState(() {
              _selectedImage = 'assets/images/preg.png';
            });
          },
          child: Image.asset(
            'assets/images/preg.png', // proj type = body
            width: 100,
            height: 100,
            color:
                _selectedImage == 'assets/images/preg.png' ? Colors.blue : null,
          ),
        ),
      ],
    );
  }

  Widget _buildTextField() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16.0),
      child: FractionallySizedBox(
        widthFactor: 1.0,
        child: TextField(
          controller: _nameController,
          onSubmitted: (_) {
            if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
              _createProject();
            }
          },
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            filled: true,
            fillColor: Colors.grey[800],
            hintText: 'Enter project name',
            hintStyle: const TextStyle(color: Colors.grey),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(6.0),
              borderSide: BorderSide.none,
            ),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 16.0, vertical: 14.0),
          ),
        ),
      ),
    );
  }

  void _createProject() async {
    final projectName = _nameController.text.trim();
    if (projectName.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Project name cannot be blank')),
      );
      return;
    }

    String projectType = 'face';
    switch (_selectedImage) {
      case 'assets/images/face.png':
        projectType = 'face';
        break;
      case 'assets/images/musc.png':
        projectType = 'musc';
        break;
      case 'assets/images/preg.png':
        projectType = 'pregnancy';
        break;
    }

    final int projectId = await DB.instance.addProject(
      projectName,
      projectType,
      DateTime.now().millisecondsSinceEpoch,
    );

    try {
      final String defaultProject =
          await DB.instance.getSettingValueByTitle('default_project');
      if (defaultProject == "none") {
        await DB.instance
            .setSettingByTitle('default_project', projectId.toString());
      }
    } catch (e) {
      LogService.instance.log("Error while setting new default project: $e");
    }

    try {
      DateTime fivePMLocalTime = NotificationUtil.getFivePMLocalTime();
      final dailyNotificationTime =
          fivePMLocalTime.millisecondsSinceEpoch.toString();

      await DB.instance.setSettingByTitle('daily_notification_time',
          dailyNotificationTime, projectId.toString());
      await NotificationUtil.initializeNotifications();
      await NotificationUtil.scheduleDailyNotification(
          projectId, dailyNotificationTime);
    } catch (e) {
      LogService.instance.log("Error while setting up notifications: $e");
    }

    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (context) => MainNavigation(
          projectId: projectId,
          projectName: projectName,
          showFlashingCircle: false,
        ),
      ),
    );
  }

  Widget _buildActionButton() {
    return FractionallySizedBox(
      widthFactor: 1.0,
      child: ElevatedButton(
        onPressed: _createProject,
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.darkerLightBlue,
          minimumSize: const Size(double.infinity, 50),
          padding: const EdgeInsets.symmetric(vertical: 18.0),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(6.0),
          ),
        ),
        child: const Text(
          "CREATE",
          style: TextStyle(
              fontSize: 15, color: Colors.white, fontWeight: FontWeight.bold),
        ),
      ),
    );
  }

  static Future<bool> photoWasTakenToday(int projectId) async {
    var photos = await DB.instance.getPhotosByProjectID(projectId);
    final DateTime today = DateTime.now();
    return photos.any((photo) {
      final timestampInt = int.parse(photo['timestamp']!);
      final photoDate = DateTime.fromMillisecondsSinceEpoch(timestampInt);
      return photoDate.isSameDate(today);
    });
  }
}
