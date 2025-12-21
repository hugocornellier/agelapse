import 'package:flutter/material.dart';

class TutorialPage extends StatelessWidget {
  const TutorialPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Tutorials'),
      ),
      body: Theme(
        data: Theme.of(context).copyWith(
          dividerColor: Colors.grey.shade700,
          expansionTileTheme: const ExpansionTileThemeData(
            iconColor: Colors.grey,
            collapsedIconColor: Colors.grey,
            childrenPadding: EdgeInsets.fromLTRB(0, 0, 16, 0),
          ),
        ),
        child: ListView(
          children: [
            TutorialSection(
              title: 'Import photos',
              steps: [
                Text('1. Open the Gallery.', style: TextStyle(fontSize: 13.5)),
                SizedBox(height: 16),
                Image.asset('assets/images/open_gallery_tut.png'),
                SizedBox(height: 16),
                Divider(),
                SizedBox(height: 16),
                Text('2. Tap the upward arrow in the upper right corner.',
                    style: TextStyle(fontSize: 13.5)),
                SizedBox(height: 16),
                Image.asset('assets/images/import_tut_1.png'),
                SizedBox(height: 16),
                Divider(),
                SizedBox(height: 16),
                Text('3. Select your import method.',
                    style: TextStyle(fontSize: 13.5)),
                SizedBox(height: 16),
                Image.asset('assets/images/import_tut_2.jpg'),
                SizedBox(height: 16),
                Divider(),
                SizedBox(height: 16),
                Text(
                    '4. Importing a large quantity of photos? Import a .zip file: AgeLapse will extract and process the contents.',
                    style: TextStyle(fontSize: 13.5)),
                SizedBox(height: 16),
              ],
            ),
            TutorialSection(
              title: 'Export photos',
              steps: [
                Text('1. Open the Gallery.', style: TextStyle(fontSize: 13.5)),
                SizedBox(height: 16),
                Image.asset('assets/images/open_gallery_tut.png'),
                SizedBox(height: 16),
                Divider(),
                SizedBox(height: 16),
                Text('2. Tap the downward arrow in the upper right corner.',
                    style: TextStyle(fontSize: 13.5)),
                SizedBox(height: 16),
                Image.asset('assets/images/export_tut1.png'),
                SizedBox(height: 16),
                Divider(),
                SizedBox(height: 16),
                Text(
                    '3. Select the photo types to export. Options: the original (raw) photos, the stabilized photos, or both.',
                    style: TextStyle(fontSize: 13.5)),
                SizedBox(height: 16),
                Image.asset('assets/images/export_tut2.jpg'),
                SizedBox(height: 16),
                Text(
                    '4. Wait a moment for your files to be archived. When complete, an option will appear to save your .zip file.',
                    style: TextStyle(fontSize: 13.5)),
              ],
            ),
            TutorialSection(
              title: 'Stabilize photos',
              steps: [
                Text('1. Take or import photos into AgeLapse.',
                    style: TextStyle(fontSize: 13.5)),
                SizedBox(height: 16),
                Divider(),
                SizedBox(height: 16),
                Text(
                    '2. Photos are auto-stabilized automatically. You\'ll notice a blue progress bar in the upper portion of the app.',
                    style: TextStyle(fontSize: 13.5)),
                SizedBox(height: 16),
                Image.asset('assets/images/stab_tut1.jpg'),
                SizedBox(height: 16),
                Divider(),
                SizedBox(height: 16),
                Text(
                    '3. Open your Gallery and tap the "Stabilized" tab to view the images being stabilized in real-time.',
                    style: TextStyle(fontSize: 13.5)),
                SizedBox(height: 16),
                Image.asset('assets/images/stab_tut2.jpg'),
                SizedBox(height: 16),
                Divider(),
              ],
            ),
            TutorialSection(
              title: 'Update output position',
              steps: [
                Text('1. Tap on the Settings icon to open the settings menu.',
                    style: TextStyle(fontSize: 13.5)),
                SizedBox(height: 16),
                Image.asset('assets/images/set_eyes_tut1.png'),
                SizedBox(height: 16),
                Divider(),
                SizedBox(height: 16),
                Text(
                    '2. Locate the \'Eye position\' setting under Video Settings and tap \'Configure\'',
                    style: TextStyle(fontSize: 13.5)),
                SizedBox(height: 16),
                Image.asset('assets/images/set_eyes_tut2.png'),
                SizedBox(height: 16),
                Divider(),
                SizedBox(height: 16),
                Text(
                    '3. Drag the horizontal line up or down to adjust the vertical offset.',
                    style: TextStyle(fontSize: 13.5)),
                SizedBox(height: 8),
                Text(
                    'Drag either vertical line left or right to adjust the inter-eye spacing.',
                    style: TextStyle(fontSize: 13.5)),
                SizedBox(height: 16),
                Image.asset('assets/images/set_eyes_tut3.png'),
                SizedBox(height: 16),
                Divider(),
                SizedBox(height: 16),
                Text(
                    '4. When satisfied, tap the Save button at the top right corner.',
                    style: TextStyle(fontSize: 13.5)),
                SizedBox(height: 16),
                Image.asset('assets/images/set_eyes_tut4.png'),
              ],
            ),
            TutorialSection(
              title: 'Create or view video',
              steps: [
                Text(
                    '1. Open the "play video" page, the fourth option in the navigation bar.',
                    style: TextStyle(fontSize: 13.5)),
                SizedBox(height: 16),
                Image.asset('assets/images/create_vid_tut1.png'),
                SizedBox(height: 16),
                Divider(),
                SizedBox(height: 16),
                Text(
                    '2. If you have two or more photos, your video will automatically compile.',
                    style: TextStyle(fontSize: 13.5)),
                SizedBox(height: 16),
                Image.asset('assets/images/create_vid_tut2.jpg'),
                SizedBox(height: 16),
                Divider(),
                SizedBox(height: 16),
                Text(
                    '3. Adjust the output settings (resolution, orientation, FPS, watermark).',
                    style: TextStyle(fontSize: 13.5)),
                SizedBox(height: 16),
                Image.asset('assets/images/create_vid_tut3.png'),
              ],
            ),
            TutorialSection(
              title: 'Create new project',
              steps: [
                Text('1. Tap your project icon to open the projects menu.',
                    style: TextStyle(fontSize: 13.5)),
                SizedBox(height: 16),
                Image.asset('assets/images/create_proj_tut1.png'),
                SizedBox(height: 16),
                Divider(),
                SizedBox(height: 16),
                Text('2. Tap the + icon to create a new project.',
                    style: TextStyle(fontSize: 13.5)),
                SizedBox(height: 16),
                Image.asset('assets/images/create_proj_tut2.png'),
                SizedBox(height: 16),
                Divider(),
                SizedBox(height: 16),
                Text(
                    '3. Select your pose and enter a project name, then hit "Create".',
                    style: TextStyle(fontSize: 13.5)),
                SizedBox(height: 16),
                Image.asset('assets/images/create_proj_tut3.png'),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class TutorialSection extends StatefulWidget {
  const TutorialSection({
    super.key,
    required this.title,
    required this.steps,
  });

  final String title;
  final List<Widget> steps;

  @override
  _TutorialSectionState createState() => _TutorialSectionState();
}

class _TutorialSectionState extends State<TutorialSection> {
  bool _isExpanded = false;

  @override
  Widget build(BuildContext context) {
    return ExpansionTile(
      title: Text(
        widget.title,
        style: TextStyle(
          fontWeight: _isExpanded ? FontWeight.bold : FontWeight.normal,
        ),
      ),
      onExpansionChanged: (bool expanded) {
        setState(() {
          _isExpanded = expanded;
        });
      },
      children: [
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: widget.steps,
          ),
        ),
      ],
    );
  }
}
