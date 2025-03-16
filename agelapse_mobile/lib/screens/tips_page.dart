import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../styles/styles.dart';

class TipsPage extends StatefulWidget {
  final int projectId;
  final String projectName;
  final Function goToPage;

  const TipsPage({
    super.key,
    required this.projectId,
    required this.projectName,
    required this.goToPage,
  });

  @override
  TipsPageState createState() => TipsPageState();
}

class TipsPageState extends State<TipsPage> {
  final Color appBarColor = const Color(0xff151517);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        backgroundColor: appBarColor,
        title: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              "Tips",
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            IconButton(
              icon: const Icon(Icons.close, size: 30),
              onPressed: () => closePage(),
            ),
          ],
        ),
      ),
      body: _buildBody(),
    );
  }

  Container _buildBody() {
    return Container(
      color: appBarColor,
      child: _buildTipsPage(),
    );
  }

  Widget _buildTipsPage() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.start,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Divider(
              color: Colors.grey,
              thickness: 1,
              height: 16,
            ),
            Expanded(child: Container()),
            const CustomWidget(
              title: "Look At Camera Lens",
              description: "For best results, face your camera directly and look at the lens.",
              icon: Icons.tips_and_updates,
            ),
            const SizedBox(height: 16),
            const CustomWidget(
              title: "Consistent Facial Expression",
              description: "To emphasize the gradual changes, maintain a consistent expression.",
              icon: Icons.balance,
            ),
            const SizedBox(height: 16),
            CustomWidget(
              title: "Let Us Handle the Heavy Lifting",
              description: "No need to be perfect: sit back as your photos are auto-stabilized.",
              svgIcon: SvgPicture.asset(
                'assets/relax.svg',
                width: 24,
                height: 24,
                colorFilter: const ColorFilter.mode(Colors.white, BlendMode.srcIn),
              ),
            ),
            Expanded(child: Container()),
            _buildActionButton("Start Taking Photos", 1),
            const SizedBox(height: 64),
          ],
        ),
      ),
    );
  }

  Widget _buildActionButton(String text, int index) {
    return FractionallySizedBox(
      widthFactor: 1.0,
      child: ElevatedButton(
        onPressed: () => openCamera(),
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

  void openCamera() {
    closePage();
    widget.goToPage(2);
  }

  void closePage() {
    Navigator.of(context).pop();
  }
}

class CustomWidget extends StatelessWidget {
  final String title;
  final String description;
  final IconData? icon;
  final SvgPicture? svgIcon;

  const CustomWidget({
    super.key,
    required this.title,
    required this.description,
    this.icon,
    this.svgIcon,
  }) : assert(icon != null || svgIcon != null, 'Either icon or svgIcon must be provided');

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(23.0),
      decoration: BoxDecoration(
        color: const Color(0xff212121),
        borderRadius: BorderRadius.circular(16.0),
        border: Border.all(
          color: Colors.grey.shade800,
          width: 0.7,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (icon != null)
                Icon(
                  icon,
                  color: Colors.white,
                  size: 24.0,
                )
              else if (svgIcon != null)
                svgIcon!,
              const SizedBox(width: 8.0),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 18.0,
                    fontWeight: FontWeight.bold,
                    height: 1.0,
                    color: Colors.white,
                  ),
                  softWrap: true,
                  overflow: TextOverflow.visible,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14.0),
          Text(
            description,
            style: const TextStyle(
              fontSize: 13.7,
              height: 1.6,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }
}
