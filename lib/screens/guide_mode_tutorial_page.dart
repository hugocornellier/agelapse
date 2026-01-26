import 'package:flutter/material.dart';
import 'package:smooth_page_indicator/smooth_page_indicator.dart';
import '../services/database_helper.dart';
import '../styles/styles.dart';
import '../utils/settings_utils.dart';
import '../utils/utils.dart';
import '../widgets/main_navigation.dart';

class GuideModeTutorialPage extends StatefulWidget {
  final int projectId;
  final String projectName;
  final Function(int p1) goToPage;
  final String sourcePage;

  const GuideModeTutorialPage({
    super.key,
    required this.projectId,
    required this.projectName,
    required this.goToPage,
    required this.sourcePage,
  });

  @override
  GuideModeTutorialPageState createState() => GuideModeTutorialPageState();
}

class GuideModeTutorialPageState extends State<GuideModeTutorialPage> {
  final PageController _pageController = PageController();
  int _currentPage = 0;

  @override
  void initState() {
    super.initState();
    _initialize();
    _pageController.addListener(_onPageChanged);
  }

  @override
  void dispose() {
    _pageController.removeListener(_onPageChanged);
    _pageController.dispose();
    super.dispose();
  }

  void _onPageChanged() {
    if (mounted) {
      setState(() {
        _currentPage = _pageController.page!.round();
      });
    }
  }

  void _initialize() async {
    SettingsUtil.setHasSeenGuideModeTutToTrue(widget.projectId.toString());
  }

  @override
  Widget build(BuildContext context) {
    final appBarColor = AppColors.background;
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: const Text(""),
        backgroundColor: appBarColor,
        actions: [
          IconButton(
            icon: const Icon(Icons.close),
            onPressed: () => goToCamera(),
          ),
        ],
      ),
      body: Container(color: appBarColor, child: _buildGuideModeTutorialPage()),
    );
  }

  Widget _buildGuideModeTutorialPage() {
    RichText tipText;
    switch (_currentPage) {
      case 0:
        tipText = RichText(
          textAlign: TextAlign.center,
          text: TextSpan(
            style: TextStyle(
                fontSize: AppTypography.md, color: AppColors.textPrimary),
            children: [
              TextSpan(
                text: 'Ghost Mode: ',
                style: TextStyle(
                    fontWeight: FontWeight.bold, color: AppColors.textPrimary),
              ),
              TextSpan(
                text:
                    'Overlay a faint, stabilized photo. Align your face with the ghost image.',
                style: TextStyle(color: AppColors.textPrimary),
              ),
            ],
          ),
        );
        break;
      case 1:
        tipText = RichText(
          textAlign: TextAlign.center,
          text: TextSpan(
            style: TextStyle(
                fontSize: AppTypography.md, color: AppColors.textPrimary),
            children: [
              TextSpan(
                text: 'Grid Mode: ',
                style: TextStyle(
                    fontWeight: FontWeight.bold, color: AppColors.textPrimary),
              ),
              TextSpan(
                text:
                    'Align eyes on intersecting points. Tap "Modify Grid" to customize.',
                style: TextStyle(color: AppColors.textPrimary),
              ),
            ],
          ),
        );
        break;
      case 2:
        tipText = RichText(
          textAlign: TextAlign.center,
          text: TextSpan(
            style: TextStyle(
                fontSize: AppTypography.md, color: AppColors.textPrimary),
            children: [
              TextSpan(
                text: 'Grid Mode (Ghost): ',
                style: TextStyle(
                    fontWeight: FontWeight.bold, color: AppColors.textPrimary),
              ),
              TextSpan(
                text:
                    'combines grid lines with a ghost image for precise alignment.',
                style: TextStyle(color: AppColors.textPrimary),
              ),
            ],
          ),
        );
        break;
      default:
        tipText = RichText(
          textAlign: TextAlign.center,
          text: TextSpan(
              style: TextStyle(
                  fontSize: AppTypography.md, color: AppColors.textPrimary),
              text: ''),
        );
    }

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const SizedBox(height: 48),
            const Text(
              "Introducing Guides",
              style: TextStyle(
                  fontSize: AppTypography.display, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            ClipRRect(
              borderRadius: BorderRadius.circular(16.0),
              child: Container(
                color: AppColors.surfaceElevated,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16.0,
                    vertical: 8.0,
                  ),
                  child: Column(
                    children: [
                      const SizedBox(height: 16),
                      SizedBox(
                        height: 250,
                        width: double.infinity,
                        child: PageView(
                          controller: _pageController,
                          children: [
                            _buildPage("Ghost Mode"),
                            _buildPage("Grid Mode (Simple)"),
                            _buildPage("Grid Mode (Ghost)"),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      tipText,
                      const SizedBox(height: 16),
                      SmoothPageIndicator(
                        controller: _pageController,
                        count: 3,
                        effect: WormEffect(
                          dotHeight: 6,
                          dotWidth: 6,
                          activeDotColor: AppColors.textPrimary,
                          dotColor: AppColors.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],
                  ),
                ),
              ),
            ),
            Expanded(child: Container()),
            _buildActionButton("Try It Out"),
            const SizedBox(height: 48),
          ],
        ),
      ),
    );
  }

  Widget _buildPage(String guideMode) {
    final String imagePath;
    if (guideMode == "Ghost Mode") {
      imagePath = 'assets/images/ghost_face.png';
    } else if (guideMode == "Grid Mode (Ghost)") {
      imagePath = 'assets/images/stable_ghost.png';
    } else {
      imagePath = 'assets/images/stable_face.png';
    }

    return Center(
      child: Column(
        children: [
          ClipOval(
            child: Image.asset(
              imagePath,
              width: 200,
              height: 200,
              fit: BoxFit.cover,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButton(String text) {
    return FractionallySizedBox(
      widthFactor: 1.0,
      child: ElevatedButton(
        onPressed: () async {
          await DB.instance.setSettingByTitle(
            'grid_mode_index',
            1.toString(),
            widget.projectId.toString(),
          );

          goToCamera();
        },
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.accentDark,
          minimumSize: const Size(double.infinity, 50),
          padding: const EdgeInsets.symmetric(vertical: 18.0),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(6.0),
          ),
        ),
        child: Text(
          text.toUpperCase(),
          style: TextStyle(
            fontSize: AppTypography.lg,
            color: AppColors.textPrimary,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  void goToCamera() {
    Utils.navigateToScreenReplaceNoAnim(
      context,
      MainNavigation(
        projectId: widget.projectId,
        projectName: widget.projectName,
        showFlashingCircle: false,
        index: 2,
      ),
    );
  }
}
