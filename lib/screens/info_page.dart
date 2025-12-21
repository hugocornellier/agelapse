import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter_email_sender/flutter_email_sender.dart';
import 'package:material_symbols_icons/material_symbols_icons.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/log_service.dart';
import '../styles/styles.dart';
import '../utils/utils.dart';
import '../widgets/fancy_button.dart';
import 'tutorial_page.dart';
import 'faq_page.dart';

class InfoPage extends StatefulWidget {
  final int projectId;
  final String projectName;
  final Future<void> Function() cancelStabCallback;
  final Function(int) goToPage;
  final bool stabilizingRunningInMain;

  const InfoPage({
    super.key,
    required this.projectId,
    required this.projectName,
    required this.cancelStabCallback,
    required this.stabilizingRunningInMain,
    required this.goToPage,
  });

  @override
  InfoPageState createState() => InfoPageState();
}

class InfoPageState extends State<InfoPage>
    with SingleTickerProviderStateMixin {
  bool noPhotos = false;
  bool? isLightTheme;
  bool hasTakenMoreThanOnePhoto = false;
  bool hasOpenedNonEmptyGallery = false;
  bool hasViewedFirstVideo = false;
  bool hasOpenedNotifications = false;
  int photoCount = 0;

  Future<void> _sendEmail(String email, String subject) async {
    if (Platform.isAndroid || Platform.isIOS) {
      final Email emailToSend = Email(
        body: '',
        subject: subject,
        recipients: [email],
        isHTML: false,
      );
      try {
        await FlutterEmailSender.send(emailToSend);
      } catch (error) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open email app')),
        );
      }
    } else {
      final uri = Uri(
        scheme: 'mailto',
        path: email,
        queryParameters: {'subject': subject},
      );
      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!ok && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No default mail client found')),
        );
      }
    }
  }

  Future<void> _openDocumentation() async {
    final uri = Uri.parse('https://agelapse.com/docs/intro/');
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open Documentation')),
      );
    }
  }

  Future<void> _exportLogs() async {
    try {
      await LogService.instance.exportLogs();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not export logs')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.darkGrey,
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        const SizedBox(height: 30),
                        _buildSectionTitle('Help', ""),
                        const SizedBox(height: 30),
                        FancyButton.buildElevatedButton(
                          context,
                          text: 'Documentation',
                          icon: Symbols.diamond_shine,
                          color: AppColors.lessDarkGrey,
                          onPressed: _openDocumentation,
                        ),
                        const SizedBox(height: 20),
                        FancyButton.buildElevatedButton(
                          context,
                          text: 'Tutorials',
                          icon: Icons.menu_book_outlined,
                          color: AppColors.lessDarkGrey,
                          onPressed: () => Utils.navigateToScreen(
                              context, const TutorialPage()),
                        ),
                        const SizedBox(height: 20),
                        FancyButton.buildElevatedButton(
                          context,
                          text: 'F.A.Q.',
                          icon: Icons.question_mark,
                          color: AppColors.lessDarkGrey,
                          onPressed: () =>
                              Utils.navigateToScreen(context, FAQPage()),
                        ),
                        const SizedBox(height: 50),
                        _buildSectionTitle('Contact Us', ""),
                        const SizedBox(height: 30),
                        FancyButton.buildElevatedButton(
                          context,
                          text: 'Report Bugs',
                          icon: Icons.bug_report_sharp,
                          color: AppColors.lessDarkGrey,
                          onPressed: () => _sendEmail(
                              'agelapse+bugs@gmail.com', 'Bug Report'),
                        ),
                        const SizedBox(height: 20.0),
                        FancyButton.buildElevatedButton(
                          context,
                          text: 'Suggest Features',
                          icon: Icons.info_outline,
                          color: AppColors.lessDarkGrey,
                          onPressed: () => _sendEmail(
                              'agelapse+features@gmail.com',
                              'Feature Suggestion'),
                        ),
                        const SizedBox(height: 20.0),
                        FancyButton.buildElevatedButton(
                          context,
                          text: 'Export Logs',
                          icon: Icons.description_outlined,
                          color: AppColors.lessDarkGrey,
                          onPressed: _exportLogs,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(String title, String step) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          title,
          style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w600),
        ),
        Align(
          alignment: Alignment.centerRight,
          child: Text(
            step,
            style: const TextStyle(
              fontSize: 14,
              color: Colors.grey,
            ),
          ),
        ),
      ],
    );
  }
}
