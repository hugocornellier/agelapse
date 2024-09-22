import 'package:agelapse/screens/create_project_page.dart';
import 'package:flutter/material.dart';
import '../../styles/styles.dart';

class WelcomePagePartTwo extends StatefulWidget {
  const WelcomePagePartTwo({super.key});

  @override
  WelcomePagePartTwoState createState() => WelcomePagePartTwoState();
}

class WelcomePagePartTwoState extends State<WelcomePagePartTwo> {
  final Color backgroundColor = const Color(0xff151517);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(""),
        backgroundColor: backgroundColor,
      ),
      body: _buildBody(),
    );
  }

  Container _buildBody() {
    return Container(
      color: backgroundColor,
      child: _buildFirstPhotoPage(),
    );
  }

  Widget _buildFirstPhotoPage() {
    const double imageDiameter = 200;
    const String imagePath = 'assets/images/stable_face.png';

    return Center(
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
                style: const TextStyle(fontSize: 26, color: Colors.white, fontWeight: FontWeight.bold),
                children: <InlineSpan>[
                  WidgetSpan(
                    child: GradientText(
                      'Auto-Stabilization',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 27.5,
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
              style: TextStyle(fontSize: 15),
              textAlign: TextAlign.center,
            ),
            Expanded(child: Container()),
            _buildActionButton("Create Project"),
            const SizedBox(height: 64),
          ],
        ),
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

  void navigateToNextPage({bool? takingGuidePhoto}) {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (context) => const CreateProjectPage(
        showCloseButton: false
      ))
    );
  }
}

class GradientText extends StatelessWidget {
  final String text;
  final TextStyle style;

  GradientText(this.text, {required this.style});

  @override
  Widget build(BuildContext context) {
    return ShaderMask(
      shaderCallback: (bounds) => LinearGradient(
        colors: [Colors.blue, Colors.purple.shade500],
        tileMode: TileMode.mirror,
      ).createShader(bounds),
      child: Text(
        text,
        style: style.copyWith(color: Colors.white),
      ),
    );
  }
}
