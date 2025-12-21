import 'package:flutter/material.dart';
import '../styles/styles.dart';

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
  final Color appBarColor = const Color(0xff151517);

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
      child: _buildTookFirstPhotoPage(),
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
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            const Text(
              "Photos are stored in your Gallery. View the "
              "original and/or stabilized version.",
              style: TextStyle(fontSize: 14),
              textAlign: TextAlign.center,
            ),
            Expanded(child: Container()),
            _buildActionButton("View Gallery"),
            const SizedBox(height: 16),
            const Text(
              "This is the beginning of something great. We can feel it!",
              style: TextStyle(fontSize: 12, color: Colors.grey),
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

    return FractionallySizedBox(
      widthFactor: 1.0,
      child: ElevatedButton(
        onPressed: () => navigateToIndex(takingGuidePhoto: takingGuidePhoto),
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

  void navigateToIndex({bool? takingGuidePhoto}) {
    Navigator.pop(context);
    widget.goToPage(1);
  }

  void close() {
    Navigator.pop(context);
    widget.goToPage(0);
  }
}
