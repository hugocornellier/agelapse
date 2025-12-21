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
  final Color appBarColor = const Color(0xff151517);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(""),
        backgroundColor: appBarColor,
        automaticallyImplyLeading: false,
        actions: [
          IconButton(
            icon: const Icon(Icons.close),
            onPressed: () => close(),
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Container _buildBody() {
    return Container(
      color: appBarColor,
      child: _buildCreateFirstVideoPage(),
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

  Widget _buildCreateFirstVideoPage() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const SizedBox(height: 32),
          _buildWaveImage(),
          const SizedBox(height: 96),
          const Text(
            "Your First Video",
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 32),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16.0),
            child: Text(
              "Once your second photo is taken, AgeLapse will automatically compile a stabilized video.",
              style: TextStyle(fontSize: 14),
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
              fontSize: 15, color: Colors.white, fontWeight: FontWeight.bold),
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
