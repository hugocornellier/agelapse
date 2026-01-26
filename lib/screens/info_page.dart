import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter_email_sender/flutter_email_sender.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/log_service.dart';
import '../styles/styles.dart';
import '../utils/utils.dart';
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

class InfoPageState extends State<InfoPage> {
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
      backgroundColor: AppColors.background,
      body: LayoutBuilder(
        builder: (context, constraints) {
          final screenWidth = constraints.maxWidth;
          final isDesktop = screenWidth >= 600;
          final maxContentWidth = isDesktop ? 520.0 : screenWidth;

          return SingleChildScrollView(
            child: Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: maxContentWidth),
                child: Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: isDesktop ? 32.0 : 20.0,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 32),
                      _buildSection(
                        title: 'Help',
                        icon: Icons.help_outline_rounded,
                        items: [
                          _InfoItem(
                            title: 'Documentation',
                            subtitle: 'Browse the online docs',
                            icon: Icons.auto_awesome_rounded,
                            onTap: _openDocumentation,
                          ),
                          _InfoItem(
                            title: 'Tutorials',
                            subtitle: 'Step-by-step guides',
                            icon: Icons.menu_book_outlined,
                            onTap: () => Utils.navigateToScreen(
                              context,
                              const TutorialPage(),
                            ),
                          ),
                          _InfoItem(
                            title: 'F.A.Q.',
                            subtitle: 'Frequently asked questions',
                            icon: Icons.quiz_outlined,
                            onTap: () => Utils.navigateToScreen(
                              context,
                              FAQPage(),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),
                      _buildSection(
                        title: 'Contact Us',
                        icon: Icons.mail_outline_rounded,
                        items: [
                          _InfoItem(
                            title: 'Report Bugs',
                            subtitle: 'Help us improve AgeLapse',
                            icon: Icons.bug_report_outlined,
                            onTap: () => _sendEmail(
                              'agelapse+bugs@gmail.com',
                              'Bug Report',
                            ),
                          ),
                          _InfoItem(
                            title: 'Suggest Features',
                            subtitle: 'Share your ideas',
                            icon: Icons.lightbulb_outline_rounded,
                            onTap: () => _sendEmail(
                              'agelapse+features@gmail.com',
                              'Feature Suggestion',
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),
                      _buildSection(
                        title: 'Advanced',
                        icon: Icons.settings_outlined,
                        items: [
                          _InfoItem(
                            title: 'Export Logs',
                            subtitle: 'For troubleshooting issues',
                            icon: Icons.description_outlined,
                            onTap: _exportLogs,
                          ),
                        ],
                      ),
                      const SizedBox(height: 48),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildSection({
    required String title,
    required IconData icon,
    required List<_InfoItem> items,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 12),
          child: Row(
            children: [
              Icon(
                icon,
                size: 18,
                color: AppColors.textSecondary,
              ),
              const SizedBox(width: 8),
              Text(
                title.toUpperCase(),
                style: TextStyle(
                  fontSize: AppTypography.sm,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textSecondary,
                  letterSpacing: 1.2,
                ),
              ),
            ],
          ),
        ),
        Container(
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: AppColors.surfaceElevated,
              width: 1,
            ),
          ),
          child: Column(
            children: [
              for (int i = 0; i < items.length; i++) ...[
                _buildListTile(items[i]),
                if (i < items.length - 1)
                  Divider(
                    height: 1,
                    thickness: 1,
                    indent: 56,
                    color: AppColors.surfaceElevated,
                  ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildListTile(_InfoItem item) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: item.onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: AppColors.accent.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  item.icon,
                  size: 20,
                  color: AppColors.accent,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.title,
                      style: TextStyle(
                        fontSize: AppTypography.md,
                        fontWeight: FontWeight.w500,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      item.subtitle,
                      style: TextStyle(
                        fontSize: AppTypography.sm,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                size: 22,
                color: AppColors.textTertiary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _InfoItem {
  final String title;
  final String subtitle;
  final IconData icon;
  final VoidCallback onTap;

  const _InfoItem({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.onTap,
  });
}
