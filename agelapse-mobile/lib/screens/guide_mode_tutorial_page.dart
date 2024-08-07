import 'package:agelapse/widgets/main_navigation.dart';
import 'package:flutter/material.dart';
import 'package:smooth_page_indicator/smooth_page_indicator.dart';
import '../services/database_helper.dart';
import '../styles/styles.dart';
import '../utils/settings_utils.dart';
import '../utils/utils.dart';

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
  final Color appBarColor = const Color(0xff151517);
  final PageController _pageController = PageController();
  int _currentPage = 0;

  @override
  void initState() {
    super.initState();
    _initialize();
    _pageController.addListener(() {
      setState(() {
        _currentPage = _pageController.page!.round();
      });
    });
  }

  void _initialize() async {
    SettingsUtil.setHasSeenGuideModeTutToTrue(widget.projectId.toString());
  }

  @override
  Widget build(BuildContext context) {
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
      body: _buildBody(),
    );
  }

  Container _buildBody() {
    return Container(
      color: appBarColor,
      child: _buildGuideModeTutorialPage(),
    );
  }

  Widget _buildGuideModeTutorialPage() {
    RichText tipText;
    switch (_currentPage) {
      case 0:
        tipText = RichText(
          textAlign: TextAlign.center,
          text: const TextSpan(
            style: TextStyle(fontSize: 13.5),
            children: [
              TextSpan(text: 'Ghost Mode: ', style: TextStyle(fontWeight: FontWeight.bold)),
              TextSpan(text: 'Overlay a faint, stabilized photo. Align your face with the ghost image.'),
            ],
          ),
        );
        break;
      case 1:
        tipText = RichText(
          textAlign: TextAlign.center,
          text: const TextSpan(
            style: TextStyle(fontSize: 13.5),
            children: [
              TextSpan(text: 'Grid Mode: ', style: TextStyle(fontWeight: FontWeight.bold)),
              TextSpan(text: 'Align eyes on intersecting points. Tap "Modify Grid" to customize.'),
            ],
          ),
        );
        break;
      case 2:
        tipText = RichText(
          textAlign: TextAlign.center,
          text: const TextSpan(
            style: TextStyle(fontSize: 13.5),
            children: [
              TextSpan(text: 'Grid Mode (Ghost): ', style: TextStyle(fontWeight: FontWeight.bold)),
              TextSpan(text: 'combines grid lines with a ghost image for precise alignment.'),
            ],
          ),
        );
        break;
      default:
        tipText = RichText(
          textAlign: TextAlign.center,
          text: const TextSpan(
            style: TextStyle(fontSize: 13.5),
            text: '',
          ),
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
              style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            ClipRRect(
              borderRadius: BorderRadius.circular(16.0), // Adjust the radius as needed
              child: Container(
                color: const Color(0xff212121),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
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
                        count: 3, // Updated page count
                        effect: const WormEffect(
                          dotHeight: 6,
                          dotWidth: 6,
                          activeDotColor: Colors.white,
                          dotColor: Colors.grey,
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
