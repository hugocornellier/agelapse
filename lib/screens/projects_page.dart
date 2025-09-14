import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:window_manager/window_manager.dart';

import '../services/database_helper.dart';
import '../styles/styles.dart';
import '../widgets/main_navigation.dart';
import '../widgets/project_select_sheet.dart';
import 'welcome_page.dart';

class ProjectsPage extends StatefulWidget {
  const ProjectsPage({super.key});

  @override
  ProjectsPageState createState() => ProjectsPageState();
}

class ProjectsPageState extends State<ProjectsPage> {
  List<Map<String, dynamic>> _projects = [];
  final TextEditingController _projectNameController = TextEditingController();
  bool _introConstraintsApplied = false;
  Size? _prevSize;
  static const double _introMinHeight = 950;
  static const Size _desktopDefaultMinSize = Size(800, 450);

  @override
  void initState() {
    super.initState();
    final bool isDesktop = !kIsWeb && (Platform.isMacOS || Platform.isWindows || Platform.isLinux);
    if (!isDesktop) {
      SystemChrome.setPreferredOrientations([
        DeviceOrientation.portraitUp,
      ]);
    }
    _getProjects();
  }

  Future<void> _getProjects() async {
    final List<Map<String, dynamic>> projects = await DB.instance.getAllProjects();
    setState(() => _projects = projects);
    if (_isDesktop()) {
      if (_projects.isEmpty) {
        WidgetsBinding.instance.addPostFrameCallback((_) => _applyIntroWindowConstraints());
      } else {
        WidgetsBinding.instance.addPostFrameCallback((_) => _restoreWindowConstraints());
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool isDesktop = !kIsWeb && (Platform.isMacOS || Platform.isWindows || Platform.isLinux);

    Widget bodyContents = isDesktop
        ? (_projects.isEmpty ? _buildWelcomePageDesktop() : _buildProjectSelectScreenDesktop())
        : (_projects.isEmpty ? _buildWelcomePage() : _buildProjectSelectScreen());

    final Color backgroundColor = _projects.isEmpty
        ? const Color(0xff151517)
        : Colors.black;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: backgroundColor,
        toolbarHeight: 0,
      ),
      backgroundColor: backgroundColor,
      body: bodyContents,
    );
  }

  Widget _buildProjectSelectScreen() {
    return Column(
      children: [
        ProjectSelectionSheet(
          isDefaultProject: false,
          showCloseButton: false,
          cancelStabCallback: () {  } ,
        ),
        Expanded(
            child: Container(
              color: const Color(0xff121212),
            )
        )
      ],
    );
  }

  Widget _buildProjectSelectScreenDesktop() {
    return LayoutBuilder(
      builder: (context, constraints) {
        return Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1200),
            child: SizedBox(
              height: constraints.maxHeight,
              child: ProjectSelectionSheet(
                isDefaultProject: false,
                showCloseButton: false,
                cancelStabCallback: () {},
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildWelcomePageDesktop() {
    return LayoutBuilder(
      builder: (context, constraints) {
        return Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 900),
            child: SizedBox(
              height: constraints.maxHeight,
              child: _buildWelcomePage(),
            ),
          ),
        );
      },
    );
  }

  Widget _buildActionButton(String text) {
    return FractionallySizedBox(
      widthFactor: 1.0,
      child: ElevatedButton(
        onPressed: () => openWelcomePagePartTwo(),
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.darkerLightBlue,
          minimumSize: const Size(double.infinity, 50),
          padding: const EdgeInsets.symmetric(vertical: 18.0),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(6.0),
          ),
        ),
        child: Text(
          text.toUpperCase(),
          style: const TextStyle(
              fontSize: 15,
              color: Colors.white,
              fontWeight: FontWeight.bold
          ),
        ),
      ),
    );
  }

  void openWelcomePagePartTwo() {
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (context) => const WelcomePagePartTwo(),
      ),
    );
  }

  Widget _buildWaveImage() {
    const String imagePath = 'assets/images/wave-tc.png';

    return Image.asset(
      imagePath,
      width: double.infinity,
      fit: BoxFit.cover,
    );
  }

  Widget _buildWelcomePage() {
    return GestureDetector(
      onTap: () {
        FocusScope.of(context).unfocus();
      },
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const SizedBox(height: 32),
            _buildWaveImage(),
            const SizedBox(height: 96),
            Image.asset(
              'assets/images/agelapselogo.png',
              width: 160,
              fit: BoxFit.cover,
            ),
            const SizedBox(height: 96),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16.0),
              child: Text(
                'The most powerful tool for creating aging timelapses.'
                    '\n\n'
                    '100% free, forever.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.white,
                ),
              ),
            ),
            const SizedBox(height: 36),
            Expanded(child: Container()),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32.0),
              child: _buildActionButton("Get Started"),
            ),
            const SizedBox(height: 64),
          ],
        ),
      ),
    );
  }

  void navigateToProject(BuildContext context, Map<String, dynamic> project) {
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (context) => MainNavigation(
          projectId: project['id'],
          projectName: project['name'],
          showFlashingCircle: false,
        ),
      ),
    );
  }

  bool _isDesktop() {
    return !kIsWeb && (Platform.isMacOS || Platform.isWindows || Platform.isLinux);
  }

  Future<void> _applyIntroWindowConstraints() async {
    if (!_isDesktop() || _introConstraintsApplied) return;
    _prevSize = await windowManager.getSize();
    final currentSize = _prevSize!;
    await windowManager.setMinimumSize(Size(_desktopDefaultMinSize.width, _introMinHeight));
    if (currentSize.height < _introMinHeight) {
      await windowManager.setSize(Size(currentSize.width, _introMinHeight));
    }
    _introConstraintsApplied = true;
  }

  Future<void> _restoreWindowConstraints() async {
    if (!_isDesktop() || !_introConstraintsApplied) return;
    await windowManager.setMinimumSize(_desktopDefaultMinSize);
    if (_prevSize != null) {
      await windowManager.setSize(_prevSize!);
    }
    _introConstraintsApplied = false;
  }

  @override
  void dispose() {
    _restoreWindowConstraints();
    _projectNameController.dispose();
    super.dispose();
  }
}
