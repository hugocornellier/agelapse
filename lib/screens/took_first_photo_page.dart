import 'package:flutter/material.dart';
import '../styles/styles.dart';
import '../widgets/desktop_page_scaffold.dart';
import '../widgets/onboarding_action_button.dart';

class TookFirstPhotoPage extends StatefulWidget {
  final int projectId;
  final String projectName;
  final void Function(int index) goToPage;

  const TookFirstPhotoPage({
    super.key,
    required this.projectId,
    required this.projectName,
    required this.goToPage,
  });

  @override
  TookFirstPhotoPageState createState() => TookFirstPhotoPageState();
}

class TookFirstPhotoPageState extends State<TookFirstPhotoPage> {
  @override
  Widget build(BuildContext context) {
    final appBarColor = AppColors.background;
    return DesktopPageScaffold(
      onClose: () => close(),
      backgroundColor: AppColors.background,
      body: Container(color: appBarColor, child: _buildTookFirstPhotoPage()),
    );
  }

  Widget _buildTookFirstPhotoPage() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const SizedBox(height: 96),
            _buildFireworksImage(),
            const SizedBox(height: 64),
            const Text(
              "Your First Photo",
              style: TextStyle(
                fontSize: AppTypography.xxxl,
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            const Text(
              "Photos are stored in your Gallery. View the "
              "original and/or stabilized version.",
              style: TextStyle(fontSize: AppTypography.md),
              textAlign: TextAlign.center,
            ),
            Expanded(child: Container()),
            _buildActionButton("View Gallery"),
            const SizedBox(height: 16),
            Text(
              "This is the beginning of something great. We can feel it!",
              style: TextStyle(
                fontSize: AppTypography.sm,
                color: AppColors.textSecondary,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 64),
          ],
        ),
      ),
    );
  }

  Widget _buildFireworksImage() {
    const double imageDiameter = 200;
    const String imagePath = 'assets/images/fireworks.png';

    return ClipRect(
      child: Image.asset(
        imagePath,
        width: imageDiameter,
        height: imageDiameter,
        fit: BoxFit.cover,
      ),
    );
  }

  Widget _buildActionButton(String text) {
    bool? takingGuidePhoto = text == "Take Guide Photo";

    return OnboardingActionButton(
      text: text,
      onPressed: () => navigateToIndex(takingGuidePhoto: takingGuidePhoto),
      textColor: Colors.white,
    );
  }

  void navigateToIndex({bool? takingGuidePhoto}) {
    Navigator.pop(context);
    widget.goToPage(1);
  }

  void close() {
    Navigator.pop(context);
    widget.goToPage(0);
  }
}
