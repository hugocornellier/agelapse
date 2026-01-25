import 'package:flutter/material.dart';
import '../styles/styles.dart';
import 'create_project_page.dart';

class WelcomePagePartTwo extends StatefulWidget {
  const WelcomePagePartTwo({super.key});

  @override
  WelcomePagePartTwoState createState() => WelcomePagePartTwoState();
}

class WelcomePagePartTwoState extends State<WelcomePagePartTwo> {
  final Color backgroundColor = AppColors.background;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text(""), backgroundColor: backgroundColor),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    return ColoredBox(color: backgroundColor, child: _buildFirstPhotoPage());
  }

  Widget _buildFirstPhotoPage() {
    const double imageDiameter = 200;
    const String imagePath = 'assets/images/stable_face.png';

    return SafeArea(
      top: false,
      child: LayoutBuilder(
        builder: (context, constraints) {
          return SingleChildScrollView(
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: IntrinsicHeight(
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 18.0),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const SizedBox(height: 32),
                        ClipOval(
                          child: Image.asset(
                            imagePath,
                            width: imageDiameter,
                            height: imageDiameter,
                            fit: BoxFit.cover,
                          ),
                        ),
                        const SizedBox(height: 96),
                        RichText(
                          textAlign: TextAlign.center,
                          text: TextSpan(
                            text: 'Advanced\n',
                            style: const TextStyle(
                              fontSize: AppTypography.display,
                              color: AppColors.textPrimary,
                              fontWeight: FontWeight.bold,
                            ),
                            children: <InlineSpan>[
                              WidgetSpan(
                                child: GradientText(
                                  'Auto-Stabilization',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: AppTypography.display,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 32),
                        const Text(
                          "AgeLapse automatically aligns every photo to create "
                          "a stabilized timelapse.",
                          style: TextStyle(fontSize: AppTypography.lg),
                          textAlign: TextAlign.center,
                        ),
                        const Spacer(),
                        _buildActionButton("Create Project"),
                        const SizedBox(height: 32),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildActionButton(String text) {
    bool? takingGuidePhoto = text == "Take Guide Photo";

    return FractionallySizedBox(
      widthFactor: 1.0,
      child: ElevatedButton(
        onPressed: () => navigateToNextPage(takingGuidePhoto: takingGuidePhoto),
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
          style: const TextStyle(
            fontSize: AppTypography.lg,
            color: AppColors.textPrimary,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  void navigateToNextPage({bool? takingGuidePhoto}) {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (context) => const CreateProjectPage(
          showCloseButton: false,
          isFullPage: true,
        ),
      ),
    );
  }
}

class GradientText extends StatelessWidget {
  final String text;
  final TextStyle style;

  const GradientText(this.text, {super.key, required this.style});

  @override
  Widget build(BuildContext context) {
    return ShaderMask(
      shaderCallback: (bounds) => LinearGradient(
        colors: [AppColors.info, Colors.purple.shade500],
        tileMode: TileMode.mirror,
      ).createShader(bounds),
      child: Text(text, style: style.copyWith(color: AppColors.textPrimary)),
    );
  }
}
