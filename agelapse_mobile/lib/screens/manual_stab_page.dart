import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import '../services/face_stabilizer.dart';
import '../utils/dir_utils.dart';
import '../utils/settings_utils.dart';
import '../utils/stabilizer_utils/stabilizer_utils.dart';

class ManualStabilizationPage extends StatefulWidget {
  final String imagePath;
  final int projectId;

  const ManualStabilizationPage({
    Key? key,
    required this.imagePath,
    required this.projectId,
  }) : super(key: key);

  @override
  _ManualStabilizationPageState createState() => _ManualStabilizationPageState();
}

class _ManualStabilizationPageState extends State<ManualStabilizationPage> {
  String rawPhotoPath = "";
  Uint8List? _stabilizedImageBytes; // State variable for the stabilized image.

  // Controllers for the four input fields.
  final TextEditingController _inputController1 = TextEditingController();
  final TextEditingController _inputController2 = TextEditingController();
  final TextEditingController _inputController3 = TextEditingController();
  final TextEditingController _inputController4 = TextEditingController();

  @override
  void initState() {
    super.initState();
    init();
  }

  @override
  void dispose() {
    _inputController1.dispose();
    _inputController2.dispose();
    _inputController3.dispose();
    _inputController4.dispose();
    super.dispose();
  }

  Future<void> init() async {
    if (widget.imagePath.contains('/stabilized/')) {
      final rawPhotoPathRes = await DirUtils.getRawPhotoPathFromTimestampAndProjectId(
        p.basenameWithoutExtension(widget.imagePath),
        widget.projectId,
      );
      setState(() {
        rawPhotoPath = rawPhotoPathRes;
      });
    } else {
      setState(() {
        rawPhotoPath = widget.imagePath;
      });
    }
    print(rawPhotoPath);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Manual Stabilization'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            // Input fields and submit button.
            TextField(
              controller: _inputController1,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'Translate X',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _inputController2,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'Translate Y',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _inputController3,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'Scale Factor',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _inputController4,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'Rotation (Degrees)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 32),
            ElevatedButton(
              onPressed: () {
                double? translateX = double.tryParse(_inputController1.text);
                double? translateY = double.tryParse(_inputController2.text);
                double? scaleFactor = double.tryParse(_inputController3.text);
                double? rotationDegrees = double.tryParse(_inputController4.text);
                print('Input 1: $translateX, Input 2: $translateY, Input 3: $scaleFactor, Input 4: $rotationDegrees');
                processRequest(translateX, translateY, scaleFactor, rotationDegrees);
              },
              child: const Text('Submit'),
            ),
            const SizedBox(height: 32),
            // Display the stabilized image if available.
            if (_stabilizedImageBytes != null)
              Image.memory(
                _stabilizedImageBytes!,
                width: MediaQuery.of(context).size.width,
                fit: BoxFit.fitWidth,
              ),
          ],
        ),
      ),
    );
  }

  Future<void> processRequest(double? translateX, double? translateY, double? scaleFactor, double? rotationDegrees) async {
    try {
      final ui.Image? img = await StabUtils.loadImageFromFile(File(rawPhotoPath));
      if (img == null) {
        return;
      }

      FaceStabilizer faceStabilizer = FaceStabilizer(widget.projectId, () => print("Test"));
      final Uint8List? imageBytesStabilized = await faceStabilizer.generateStabilizedImageBytes(img, rotationDegrees, scaleFactor, translateX, translateY);
      if (imageBytesStabilized == null) {
        return;
      }

      // Update the state so that the stabilized image is shown on the screen.
      setState(() {
        _stabilizedImageBytes = imageBytesStabilized;
      });

      final String projectOrientation = await SettingsUtil.loadProjectOrientation(widget.projectId.toString());
      final String stabilizedPhotoPath = await StabUtils.getStabilizedImagePath(rawPhotoPath, widget.projectId, projectOrientation);
      final String stabThumbPath = FaceStabilizer.getStabThumbnailPath(stabilizedPhotoPath);

      // Deleting old files
      final File stabImageFile = File(stabilizedPhotoPath);
      final File stabThumbFile = File(stabThumbPath);
      if (await stabImageFile.exists()) {
        await stabImageFile.delete();
      }
      if (await stabThumbFile.exists()) {
        await stabThumbFile.delete();
      }

      print("Here3. stabilizedPhotoPath: $stabilizedPhotoPath");

      await faceStabilizer.saveStabilizedImage(imageBytesStabilized, rawPhotoPath, stabilizedPhotoPath, 0.0);
      print("Here4");

      await faceStabilizer.createStabThumbnail(stabilizedPhotoPath.replaceAll('.jpg', '.png'));
      print("Here5");

      img.dispose();
    } catch (e, stackTrace) {
      print("An error occurred in processRequest: $e");
      print("Stack trace: $stackTrace");
    }
  }
}

