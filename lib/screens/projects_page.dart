import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/database_helper.dart';
import '../styles/styles.dart';
import '../utils/platform_utils.dart';
import '../utils/utils.dart';
import '../widgets/main_navigation.dart';
import '../widgets/onboarding_action_button.dart';
import '../widgets/project_select_sheet.dart';
import 'create_project_page.dart';

class ProjectsPage extends StatefulWidget {
  const ProjectsPage({super.key});

  @override
  ProjectsPageState createState() => ProjectsPageState();
}

class ProjectsPageState extends State<ProjectsPage> {
  List<Map<String, dynamic>> _projects = [];
  final TextEditingController _projectNameController = TextEditingController();

  @override
  void initState() {
    super.initState();
    if (kIsWeb || !isDesktop) {
      SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    }
    _getProjects();
  }

  Future<void> _getProjects() async {
    final List<Map<String, dynamic>> projects =
        await DB.instance.getAllProjects();
    if (mounted) {
      setState(() => _projects = projects);
    }
  }

  @override
  Widget build(BuildContext context) {
    Widget bodyContents = !kIsWeb && isDesktop
        ? (_projects.isEmpty
            ? _buildWelcomePageDesktop()
            : _buildProjectSelectScreenDesktop())
        : (_projects.isEmpty
            ? _buildWelcomePage()
            : _buildProjectSelectScreen());

    final Color backgroundColor =
        _projects.isEmpty ? AppColors.background : AppColors.overlay;

    return Scaffold(
      appBar: AppBar(backgroundColor: backgroundColor, toolbarHeight: 0),
      backgroundColor: backgroundColor,
      body: bodyContents,
    );
  }

  Widget _buildProjectSelectScreen() {
    return ProjectSelectionSheet(
      isDefaultProject: false,
      showCloseButton: false,
      cancelStabCallback: () {},
      isFullPage: true,
    );
  }

  Widget _buildProjectSelectScreenDesktop() {
    return ProjectSelectionSheet(
      isDefaultProject: false,
      showCloseButton: false,
      cancelStabCallback: () {},
      isFullPage: true,
    );
  }

  Widget _buildWelcomePageDesktop() => _buildWelcomePage(isDesktop: true);

  Widget _buildWelcomePage({bool isDesktop = false}) {
    final double spacing = isDesktop ? 64 : 96;
    return _buildScrollableWelcome(
      children: [
        const SizedBox(height: 32),
        _buildWaveImage(),
        SizedBox(height: spacing),
        Image.asset(
          'assets/images/agelapselogo.png',
          width: 160,
          fit: BoxFit.cover,
        ),
        SizedBox(height: spacing),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0),
          child: Text(
            'The most powerful tool for creating aging timelapses.'
            '\n\n'
            '100% free, forever.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: AppTypography.md,
              color: AppColors.textPrimary,
            ),
          ),
        ),
        SizedBox(height: isDesktop ? 24 : 36),
        const Spacer(),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32.0),
          child: _buildActionButton(
            isDesktop ? "Create First Project" : "Create Project",
          ),
        ),
        SizedBox(height: isDesktop ? 32 : 64),
      ],
    );
  }

  Widget _buildActionButton(String text) {
    return OnboardingActionButton(
      text: text,
      onPressed: () => _openCreateProjectPage(),
    );
  }

  void _openCreateProjectPage() {
    Utils.navigateToScreenReplace(
      context,
      const CreateProjectPage(showCloseButton: false, isFullPage: true),
    );
  }

  Widget _buildScrollableWelcome({required List<Widget> children}) {
    return GestureDetector(
      onTap: () {
        FocusScope.of(context).unfocus();
      },
      child: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight),
                child: IntrinsicHeight(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: children,
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildWaveImage() {
    const String imagePath = 'assets/images/wave-tc.png';

    return Image.asset(imagePath, width: double.infinity, fit: BoxFit.cover);
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

  @override
  void dispose() {
    _projectNameController.dispose();
    super.dispose();
  }
}
