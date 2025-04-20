import 'package:flutter/material.dart';
import '../styles/styles.dart';
import '../utils/utils.dart';
import '../widgets/main_navigation.dart';

class ImportPage extends StatefulWidget {
  final int projectId;
  final String projectName;

  const ImportPage({
    super.key,
    required this.projectId,
    required this.projectName,
  });

  @override
  ImportPageState createState() => ImportPageState();
}

class ImportPageState extends State<ImportPage> {
  final Color backgroundColor = const Color(0xff151517);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(""),
        backgroundColor: backgroundColor,
        actions: [
          IconButton(
            icon: const Icon(Icons.close, size: 30),
            onPressed: () => navigateToIndex(0),
          ),
        ],
      ),
      body: Container(
        color: backgroundColor,
        child: _buildImportPage(),
      ),
    );
  }

  Widget _buildImportPage() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _buildLogo(),
            const SizedBox(height: 32),
            _buildHeadline("Let's Import!"),
            const SizedBox(height: 32),
            _buildImportOptions(),
            const SizedBox(height: 40),
            _buildActionButton("Import", 2),
          ],
        ),
      ),
    );
  }

  Widget _buildLogo() {
    const double imageDiameter = 100;
    const String imagePath = 'assets/images/face_lapse_logo.png';

    return ClipOval(
      child: Image.asset(
        imagePath,
        width: imageDiameter,
        height: imageDiameter,
        fit: BoxFit.cover,
      ),
    );
  }

  Widget _buildHeadline(String text) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 24,
        fontWeight: FontWeight.bold,
        color: Colors.white,
      ),
    );
  }

  Widget _buildImportOptions() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildText('To import, head to the gallery and click the import '
            'button in the upper right corner.\nThe import button will be '
            'highlighted on the following page.'),
        _buildText('A wide range of file formats are supported, including:'),
        _buildFileFormats(),
      ],
    );
  }

  Widget _buildText(String text) {
    return Text(
      text,
      style: const TextStyle(fontSize: 16, color: Colors.white),
    );
  }

  Widget _buildFileFormats() {
    return Column(
      children: [
        const SizedBox(height: 8),
        _buildText('Image:\tpng · jpg · heic · webp · avif\n'),
        const SizedBox(height: 8),
        _buildText('Archive:\t.zip'),
      ],
    );
  }

  Widget _buildActionButton(String text, int index) {
    return FractionallySizedBox(
      widthFactor: 0.92,
      child: ElevatedButton(
        onPressed: () => navigateToIndex(index),
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.darkerLightBlue,
          minimumSize: const Size(double.infinity, 50),
          padding: const EdgeInsets.symmetric(vertical: 16.0),
        ),
        child: Text(
          text.toUpperCase(),
          style: const TextStyle(
              fontSize: 16,
              color: Colors.white,
              fontWeight: FontWeight.bold
          ),
        ),
      ),
    );
  }

  void navigateToIndex(int index) {
    final projectId = widget.projectId;
    final projectName = widget.projectName;

    final destination = MainNavigation(
      projectId: projectId,
      projectName: projectName,
      index: index,
      showFlashingCircle: true,
    );

    Utils.navigateToScreenReplace(context, destination);
  }
}
