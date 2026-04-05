import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/log_service.dart';
import '../styles/styles.dart';

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
  bool _emailCopied = false;
  bool _emailHovered = false;

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
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Could not export logs')));
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
                        items: [
                          _InfoItem(
                            title: 'Documentation',
                            subtitle: 'Browse the online docs',
                            icon: Icons.auto_awesome_rounded,
                            onTap: _openDocumentation,
                          ),
                        ],
                      ),
                      const SizedBox(height: 40),
                      _buildContactSection(),
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

  void _copyEmail() {
    Clipboard.setData(const ClipboardData(text: 'agelapse@gmail.com'));
    setState(() => _emailCopied = true);
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) setState(() => _emailCopied = false);
    });
  }

  Widget _buildContactSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 12),
          child: Text(
            'CONTACT & SUPPORT',
            style: TextStyle(
              fontSize: AppTypography.sm,
              fontWeight: FontWeight.w600,
              color: AppColors.textSecondary,
              letterSpacing: 1.2,
            ),
          ),
        ),
        // Email display
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 16),
          child: Text(
            'Find a bug or have a suggestion? Email us at:',
            style: TextStyle(
              fontSize: AppTypography.md,
              color: AppColors.textPrimary,
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: MouseRegion(
            cursor: SystemMouseCursors.click,
            onEnter: (_) => setState(() => _emailHovered = true),
            onExit: (_) => setState(() => _emailHovered = false),
            child: GestureDetector(
              onTap: _copyEmail,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
                decoration: BoxDecoration(
                  color: _emailCopied
                      ? AppColors.success.withValues(alpha: 0.1)
                      : _emailHovered
                          ? AppColors.surfaceElevated
                          : AppColors.surface,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: _emailCopied
                        ? AppColors.success.withValues(alpha: 0.3)
                        : AppColors.surfaceElevated,
                    width: 1,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: _emailCopied
                            ? AppColors.success.withValues(alpha: 0.15)
                            : AppColors.accent.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 200),
                        child: _emailCopied
                            ? Icon(
                                Icons.check_rounded,
                                size: 20,
                                color: AppColors.success,
                                key: const ValueKey('check'),
                              )
                            : Icon(
                                Icons.mail_outline_rounded,
                                size: 20,
                                color: AppColors.accent,
                                key: const ValueKey('mail'),
                              ),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Text(
                      _emailCopied ? 'Copied!' : 'agelapse@gmail.com',
                      style: TextStyle(
                        fontSize: AppTypography.md,
                        fontWeight: FontWeight.w500,
                        color: _emailCopied
                            ? AppColors.success
                            : AppColors.textPrimary,
                      ),
                    ),
                    if (!_emailCopied) ...[
                      const SizedBox(width: 12),
                      Icon(
                        Icons.copy_rounded,
                        size: 16,
                        color: AppColors.textTertiary,
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 16),
          child: Text(
            'Including your logs helps us fix bugs faster.',
            style: TextStyle(
              fontSize: AppTypography.md,
              color: AppColors.textPrimary,
            ),
          ),
        ),
        // Export logs card
        Container(
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.surfaceElevated, width: 1),
          ),
          child: _buildListTile(
            _InfoItem(
              title: 'Export Logs',
              subtitle: 'For troubleshooting issues',
              icon: Icons.description_outlined,
              onTap: _exportLogs,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSection({
    required String title,
    required List<_InfoItem> items,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 12),
          child: Text(
            title.toUpperCase(),
            style: TextStyle(
              fontSize: AppTypography.sm,
              fontWeight: FontWeight.w600,
              color: AppColors.textSecondary,
              letterSpacing: 1.2,
            ),
          ),
        ),
        Container(
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.surfaceElevated, width: 1),
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
                child: Icon(item.icon, size: 20, color: AppColors.accent),
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
