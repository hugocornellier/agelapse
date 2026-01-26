import 'package:flutter/material.dart';
import '../styles/styles.dart';

class CreateFirstVideoPage extends StatefulWidget {
  final int projectId;
  final String projectName;
  final Function(int p1) goToPage;

  const CreateFirstVideoPage({
    super.key,
    required this.projectId,
    required this.projectName,
    required this.goToPage,
  });

  @override
  CreateFirstVideoPageState createState() => CreateFirstVideoPageState();
}

class CreateFirstVideoPageState extends State<CreateFirstVideoPage> {
  @override
  Widget build(BuildContext context) {
    final appBarColor = AppColors.background;
    return Scaffold(
      appBar: AppBar(
        title: const Text(""),
        backgroundColor: appBarColor,
        automaticallyImplyLeading: false,
        actions: [
          IconButton(icon: const Icon(Icons.close), onPressed: () => close()),
        ],
      ),
      body: Container(color: appBarColor, child: _buildCreateFirstVideoPage()),
    );
  }

  Widget _buildWaveImage() {
    const String imagePath = 'assets/images/wave-tc.png';

    return Image.asset(imagePath, width: double.infinity, fit: BoxFit.cover);
  }

  Widget _buildCreateFirstVideoPage() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const SizedBox(height: 32),
          _buildWaveImage(),
          const SizedBox(height: 96),
          Text(
            "Your First Video",
            style: TextStyle(
                fontSize: AppTypography.xxxl,
                fontWeight: FontWeight.bold,
                color: AppColors.textPrimary),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 32),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16.0),
            child: Text(
              "Once your second photo is taken, AgeLapse will automatically compile a stabilized video.",
              style: TextStyle(fontSize: AppTypography.md),
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(height: 36),
          Expanded(child: Container()),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32.0),
            child: _buildActionButton("Take Photo", 1),
          ),
          const SizedBox(height: 64),
        ],
      ),
    );
  }

  Widget _buildActionButton(String text, int index) {
    return FractionallySizedBox(
      widthFactor: 1.0,
      child: ElevatedButton(
        onPressed: () => navigateToCameraPage(),
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

  void navigateToCameraPage() {
    close();
    widget.goToPage(2);
  }

  void close() {
    Navigator.of(context).pop();
  }
}
