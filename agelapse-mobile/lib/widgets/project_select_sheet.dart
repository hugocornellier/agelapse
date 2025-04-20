import 'dart:io';
import 'package:AgeLapse/screens/project_page.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as path;
import '../screens/create_project_page.dart';
import '../services/database_helper.dart';
import '../styles/styles.dart';
import '../utils/dir_utils.dart';
import '../utils/notification_util.dart';
import '../utils/settings_utils.dart';
import '../utils/utils.dart';
import 'main_navigation.dart';

class ProjectSelectionSheet extends StatefulWidget {
  final bool isDefaultProject;
  final bool showCloseButton;
  final void Function() cancelStabCallback;

  const ProjectSelectionSheet({
    super.key,
    required this.isDefaultProject,
    this.showCloseButton = true,
    required this.cancelStabCallback,
  });

  @override
  ProjectSelectionSheetState createState() => ProjectSelectionSheetState();
}

class ProjectSelectionSheetState extends State<ProjectSelectionSheet> {
  List<Map<String, dynamic>> _projects = [];
  final TextEditingController _editProjectNameController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _getProjects();
  }

  Future<void> _getProjects() async {
    final List<Map<String, dynamic>> projects = await DB.instance.getAllProjects();
    setState(() => _projects = projects);
  }

  Future<void> _onNewButtonTapped() async {
    Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (context) => const CreateProjectPage()));
  }

  static Future<String> getProjectImage(int projectId) async {
    final String stabilizedDirPath = await DirUtils.getStabilizedDirPath(projectId);
    final String activeProjectOrientation = await SettingsUtil.loadProjectOrientation(projectId.toString());
    final String videoOutputPath = await DirUtils.getVideoOutputPath(projectId, activeProjectOrientation);
    final String gifPath = videoOutputPath.replaceAll(path.extension(videoOutputPath), ".gif");
    if (File(gifPath).existsSync()) return gifPath;

    final String stabilizedDirActivePath = path.join(stabilizedDirPath, activeProjectOrientation);
    String? pngPath = await checkForStabilizedImage(stabilizedDirActivePath);
    if (pngPath != null) return pngPath;

    final String stabilizedDirInactivePath = path.join(
        stabilizedDirPath,
        activeProjectOrientation == "portrait" ? "landscape" : "portrait"
    );
    pngPath = await checkForStabilizedImage(stabilizedDirInactivePath);
    if (pngPath != null) return pngPath;

    final String rawPhotoDirPath = await DirUtils.getRawPhotoDirPath(projectId);
    final Directory rawPhotoDir = Directory(rawPhotoDirPath);
    final bool dirExists = await rawPhotoDir.exists();
    if (!dirExists) return "";

    final files = rawPhotoDir.listSync();
    return files.firstWhere((file) => file is File && Utils.isImage(file.path), orElse: () => File('')).path;
  }

  static Future<String?>? checkForStabilizedImage(dirPath) async {
    final directory = Directory(dirPath);
    if (directory.existsSync()) {
      try {
        final pngFiles = directory.listSync().where((item) => item.path.endsWith('.png') && item is File).toList();
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
      width: MediaQuery.of(context).size.height * 0.9,
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
                children: _projects.map((project) => _buildProjectItem(project)).toList(),
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
                      Row(
                        children: [
                          const Text('Projects', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.white)),
                          const SizedBox(width: 12.0),
                          GestureDetector(
                            onTap: _onNewButtonTapped,
                            child: Container(
                              width: 37.0,
                              height: 27.0,
                              decoration: BoxDecoration(
                                color: AppColors.evenDarkerLightBlue,
                                shape: BoxShape.rectangle,
                                borderRadius: BorderRadius.circular(8.0),
                              ),
                              child: const Center(
                                child: Icon(Icons.add),
                              ),
                            ),
                          ),
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

  void navigateToProject(BuildContext context, Map<String, dynamic> project) {
    widget.cancelStabCallback();

    if (widget.showCloseButton) {
      Navigator.of(context).pop();
    }

    Utils.navigateToScreenReplaceNoAnim(context, MainNavigation(
      projectId: project['id'],
      projectName: project['name'],
      showFlashingCircle: false,
    ));
  }

  void _showProjectOptionsPopup(BuildContext context, Map<String, dynamic> project) {
    showModalBottomSheet(
      context: context,
      builder: (context) {
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.edit),
              title: const Text('Edit Project Name'),
              onTap: () {
                Navigator.pop(context);
                _showEditProjectNamePopup(context, project);
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete),
              title: const Text('Delete Project'),
              onTap: () {
                Navigator.pop(context);
                _showDeleteProjectPopup(context, project);
              },
            ),
          ],
        );
      },
    );
  }

  void _showEditProjectNamePopup(BuildContext context, Map<String, dynamic> project) {
    _editProjectNameController.text = project['name'];
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Edit Project Name'),
          content: TextField(
            controller: _editProjectNameController,
            decoration: const InputDecoration(hintText: 'Enter new project name'),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(context);
              },
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () async {
                final newName = _editProjectNameController.text;
                await DB.instance.updateProjectName(project['id'], newName);
                _getProjects();  // Refresh the project list
                Navigator.pop(context);
              },
              child: const Text('Submit'),
            ),
          ],
        );
      },
    );
  }

  void _showDeleteProjectPopup(BuildContext context, Map<String, dynamic> project) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Delete Project'),
          content: const Text('Are you sure you want to delete this project?'),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(context);
              },
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                _deleteProject(project['id'], context);
                Navigator.pop(context);
              },
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _deleteProject(int projectId, context) async {
    final String defaultProject = await DB.instance.getSettingValueByTitle('default_project');
    if (defaultProject == projectId.toString()) {
      DB.instance.setSettingByTitle('default_project', 'none');
    }

    final int result = await DB.instance.deleteProject(projectId);
    if (result > 0) {
      _getProjects();
      await NotificationUtil.cancelNotification(projectId);
    }

    final String projectDirPath = await DirUtils.getProjectDirPath(projectId);
    await DirUtils.deleteDirectoryContents(Directory(projectDirPath));
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

  Widget _buildProjectItem(Map<String, dynamic> project) {
    return FutureBuilder<String>(
      future: getProjectImage(project['id']),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        return FutureBuilder<bool>(
          future: photoWasTakenToday(project['id']),
          builder: (context, photoSnapshot) {
            if (photoSnapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            final bool takenToday = photoSnapshot.data ?? false;
            return InkWell(
              onTap: () => navigateToProject(context, project),
              onLongPress: () => _showProjectOptionsPopup(context, project),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 0.0),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(8.0),
                  child: Row(
                    children: [
                      CircleAvatar(
                        backgroundImage: snapshot.hasData && snapshot.data!.isNotEmpty
                            ? FileImage(File(snapshot.data!))
                            : null,
                        backgroundColor: Colors.grey,
                        radius: 24.0,
                        child: snapshot.hasData && snapshot.data!.isNotEmpty
                            ? null
                            : const Icon(Icons.person, color: Colors.white),
                      ),
                      const SizedBox(width: 16),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            project['name'],
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                          ),
                          Row(
                            children: [
                              Container(
                                width: 5.0,
                                height: 5.0,
                                decoration: BoxDecoration(
                                  color: takenToday ? Colors.greenAccent : Colors.orange,
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 8.0),
                              Text(
                                takenToday ? 'Photo taken today' : 'Photo not taken',
                                style: TextStyle(color: Colors.grey[600]),
                              ),
                            ],
                          )
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

}

class _DeleteProjectDialog extends StatefulWidget {
  final VoidCallback onDelete;
  final String projectName;

  const _DeleteProjectDialog({
    required this.onDelete,
    required this.projectName,
  });

  @override
  State<_DeleteProjectDialog> createState() => __DeleteProjectDialogState();
}

class __DeleteProjectDialogState extends State<_DeleteProjectDialog> {
  final TextEditingController _controller = TextEditingController();
  bool _isNameCorrect = false;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_validateName);
  }

  void _validateName() {
    setState(() {
      _isNameCorrect = _controller.text.trim() == widget.projectName;
    });
  }

  @override
  void dispose() {
    _controller.removeListener(_validateName);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text("Delete Project"),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text("Are you sure you want to delete this project? Type the project name (${widget.projectName}) to confirm."),
          const SizedBox(height: 8),
          TextField(
            controller: _controller,
            decoration: const InputDecoration(
              hintText: "Project name",
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text("Cancel"),
        ),
        TextButton(
          onPressed: _isNameCorrect ? widget.onDelete : null,
          child: const Text("Delete"),
        ),
      ],
    );
  }
}
