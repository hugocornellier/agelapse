import 'dart:async';

import 'package:flutter/material.dart';
import '../services/settings_cache.dart';
import '../services/stab_update_event.dart';
import '../styles/styles.dart';
import '../utils/settings_utils.dart';
import '../utils/utils.dart';
import '../widgets/fancy_button.dart';
import '../widgets/grid_painter_se.dart';
import '../widgets/info_tooltip_icon.dart';
import '../utils/output_image_loader.dart';
import 'create_first_video_page.dart';
import 'guide_mode_tutorial_page.dart';
import 'tips_page.dart';

class ProjectPage extends StatefulWidget {
  final int projectId;
  final String projectName;
  final Future<void> Function() cancelStabCallback;
  final Function(int) goToPage;
  final bool stabilizingRunningInMain;
  final Future<void> Function() stabCallback;
  final Future<void> Function() setUserOnImportTutorialTrue;
  final SettingsCache? settingsCache;
  final Future<void> Function() refreshSettings;
  final void Function() clearRawAndStabPhotos;
  final Future<void> Function() recompileVideoCallback;
  final bool photoTakenToday;
  final Stream<StabUpdateEvent>? stabUpdateStream;

  const ProjectPage({
    super.key,
    required this.projectId,
    required this.projectName,
    required this.cancelStabCallback,
    required this.stabilizingRunningInMain,
    required this.goToPage,
    required this.stabCallback,
    required this.setUserOnImportTutorialTrue,
    required this.settingsCache,
    required this.refreshSettings,
    required this.clearRawAndStabPhotos,
    required this.recompileVideoCallback,
    required this.photoTakenToday,
    this.stabUpdateStream,
  });

  @override
  ProjectPageState createState() => ProjectPageState();
}

class ProjectPageState extends State<ProjectPage> {
  bool _loading = true;
  late int framerate;
  late OutputImageLoader outputImageLoader;

  StreamSubscription<StabUpdateEvent>? _stabUpdateSubscription;
  Timer? _guideImageDebounce;

  @override
  void initState() {
    super.initState();
    outputImageLoader = OutputImageLoader(widget.projectId);
    _initializePage();
    _subscribeToStabUpdates();
  }

  @override
  void dispose() {
    _guideImageDebounce?.cancel();
    _stabUpdateSubscription?.cancel();
    outputImageLoader.dispose();
    super.dispose();
  }

  void _subscribeToStabUpdates() {
    if (widget.stabUpdateStream == null) return;

    _stabUpdateSubscription = widget.stabUpdateStream!.listen((event) {
      if (!mounted) return;

      // For completion events, update immediately without debounce
      if (event.isCompletionEvent) {
        _tryUpdateGuideImage();
        return;
      }

      // Debounce normal progress updates to prevent excessive DB queries
      _guideImageDebounce?.cancel();
      _guideImageDebounce = Timer(const Duration(milliseconds: 500), () {
        _tryUpdateGuideImage();
      });
    });
  }

  Future<void> _tryUpdateGuideImage() async {
    if (!mounted) return;

    final didLoad = await outputImageLoader.tryLoadRealGuideImage();
    if (didLoad && mounted) {
      setState(() {});
    }
  }

  @override
  void didUpdateWidget(ProjectPage oldWidget) {
    super.didUpdateWidget(oldWidget);

    final oldCache = oldWidget.settingsCache;
    final newCache = widget.settingsCache;

    if (oldCache != null && newCache != null) {
      final orientationChanged =
          oldCache.projectOrientation != newCache.projectOrientation;
      final aspectRatioChanged = oldCache.aspectRatio != newCache.aspectRatio;

      if (orientationChanged || aspectRatioChanged) {
        // Settings changed - reset preview to placeholder and reload
        _handleSettingsChange();
      } else {
        // Check if only eye offsets changed (no need to reset guide image)
        final eyeOffsetChanged = oldCache.eyeOffsetX != newCache.eyeOffsetX ||
            oldCache.eyeOffsetY != newCache.eyeOffsetY;

        if (eyeOffsetChanged) {
          outputImageLoader.offsetX = newCache.eyeOffsetX;
          outputImageLoader.offsetY = newCache.eyeOffsetY;
          setState(() {});
        }
      }
    }
  }

  Future<void> _handleSettingsChange() async {
    await outputImageLoader.resetToPlaceholder();
    if (mounted) {
      setState(() {});
    }

    // Attempt to load a real guide image immediately if one exists
    // for the new settings (don't wait for stabilization stream)
    await _tryUpdateGuideImage();
  }

  Future<void> _initializePage() async {
    await loadFramerate();
    if (!mounted) return;

    final cacheReady = await _waitForCache();
    if (!mounted || !cacheReady) return;

    await outputImageLoader.initialize();
    if (!mounted) return;

    setState(() {
      _loading = false;
    });
  }

  Future<void> loadFramerate() async {
    framerate = await SettingsUtil.loadFramerate(widget.projectId.toString());
  }

  Future<bool> _waitForCache({
    Duration timeout = const Duration(seconds: 30),
  }) async {
    if (widget.settingsCache != null) return true;

    final deadline = DateTime.now().add(timeout);
    while (widget.settingsCache == null && mounted) {
      if (DateTime.now().isAfter(deadline)) {
        return false;
      }
      await Future.delayed(const Duration(milliseconds: 500));
    }
    return mounted && widget.settingsCache != null;
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        backgroundColor: Color(0xff0F0F0F),
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final cache = widget.settingsCache!;

    return Scaffold(
      backgroundColor: const Color(0xff0F0F0F),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final screenWidth = constraints.maxWidth;
          final maxContentWidth = screenWidth.clamp(0.0, 1200.0);

          return SingleChildScrollView(
            child: Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: maxContentWidth),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24.0),
                  child: cache.noPhotos ||
                          !cache.hasOpenedNonEmptyGallery ||
                          !cache.hasTakenMoreThanOnePhoto ||
                          !cache.hasViewedFirstVideo
                      ? _buildNoPhotosContent(context, includeOutput: true)
                      : _buildDashboardContent(),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildNoPhotosContent(
    BuildContext context, {
    bool includeOutput = true,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const SizedBox(height: 30),
        _buildSectionTitle('Getting started', ''),
        const SizedBox(height: 21),
        ..._buildStepButtons(context, _determineStep()),
        const SizedBox(height: 40),
        _buildDashboardSection(),
      ],
    );
  }

  Widget _buildDashboardContent() {
    return _buildDashboardSection();
  }

  List<Widget> _buildStepButtons(BuildContext context, int step) {
    Color backgroundColor = AppColors.evenDarkerLightBlue;

    Widget buildFancyButton({
      required String text,
      required IconData icon,
      required VoidCallback onPressed,
    }) {
      return FancyButton.buildElevatedButton(
        context,
        text: text,
        icon: icon,
        color: const Color(0xff212121),
        backgroundColor: backgroundColor,
        onPressed: onPressed,
      );
    }

    return [
      if (step == 1) ...[
        LayoutBuilder(
          builder: (context, constraints) {
            final isDesktop = constraints.maxWidth >= 700;

            final takePhotoButton = buildFancyButton(
              text: 'Take photo',
              icon: Icons.camera_alt,
              onPressed: () => Utils.navigateToScreenNoAnim(
                context,
                TipsPage(
                  projectId: widget.projectId,
                  projectName: widget.projectName,
                  goToPage: widget.goToPage,
                ),
              ),
            );

            final importButton = buildFancyButton(
              text: 'Import photo(s)',
              icon: Icons.file_upload,
              onPressed: () async {
                await widget.setUserOnImportTutorialTrue();
                widget.goToPage(1);
              },
            );

            if (isDesktop) {
              return Row(
                children: [
                  Expanded(child: importButton),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16),
                    child: Text(
                      "OR",
                      style: TextStyle(color: Colors.grey, fontSize: 11),
                    ),
                  ),
                  Expanded(child: takePhotoButton),
                ],
              );
            }

            return Column(
              children: [
                takePhotoButton,
                const SizedBox(height: 16),
                const Row(
                  children: <Widget>[
                    SizedBox(width: 8),
                    Expanded(child: Divider(height: 0.8)),
                    SizedBox(width: 8),
                    Text("OR",
                        style: TextStyle(color: Colors.grey, fontSize: 11)),
                    SizedBox(width: 8),
                    Expanded(child: Divider(height: 0.8)),
                    SizedBox(width: 8),
                  ],
                ),
                const SizedBox(height: 16),
                importButton,
              ],
            );
          },
        ),
        const SizedBox(height: 16),
      ] else if (step == 2) ...[
        buildFancyButton(
          text: 'Open gallery',
          icon: Icons.photo_library,
          onPressed: () => widget.goToPage(1),
        ),
      ] else if (step == 3) ...[
        buildFancyButton(
          text: 'Try guide mode',
          icon: Icons.lightbulb,
          onPressed: () => Utils.navigateToScreenNoAnim(
            context,
            GuideModeTutorialPage(
              projectId: widget.projectId,
              projectName: widget.projectName,
              goToPage: widget.goToPage,
              sourcePage: "ProjectPage",
            ),
          ),
        ),
      ] else if (step == 4) ...[
        buildFancyButton(
          text: 'Create video',
          icon: Icons.video_library,
          onPressed: () => Utils.navigateToScreenNoAnim(
            context,
            CreateFirstVideoPage(
              projectId: widget.projectId,
              projectName: widget.projectName,
              goToPage: widget.goToPage,
            ),
          ),
        ),
      ] else if (step == 5) ...[
        buildFancyButton(
          text: 'View video',
          icon: Icons.video_library,
          onPressed: () => widget.goToPage(3),
        ),
      ],
    ];
  }

  Widget _buildSectionTitle(String title, String step) {
    IconData icon;
    switch (title) {
      case 'Getting started':
        icon = Icons.lightbulb_outlined;
        break;
      case 'Dashboard':
        icon = Icons.dashboard_outlined;
        break;
      case 'Output':
        icon = Icons.movie_outlined;
        break;
      default:
        icon = Icons.info_outlined;
    }

    return SizedBox(
      height: 30,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: AppColors.settingsTextSecondary),
              const SizedBox(width: 8),
              Text(
                title.toUpperCase(),
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppColors.settingsTextSecondary,
                  letterSpacing: 1.2,
                ),
              ),
              if (title == 'Output')
                const InfoTooltipIcon(
                  content:
                      'Tap the gear icon in the upper-right to change these values.',
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDashboardSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (!widget.settingsCache!.noPhotos) const SizedBox(height: 30),
        _buildSectionTitle('Dashboard', ''),
        const SizedBox(height: 16),
        dashboardWidget(),
        const SizedBox(height: 32),
        _buildOutputSection(),
      ],
    );
  }

  Widget _buildOutputSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionTitle('Output', ''),
        const SizedBox(height: 16),
        _buildModernOutputContent(),
        const SizedBox(height: 64),
      ],
    );
  }

  Widget _buildModernOutputContent() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final availableWidth = constraints.maxWidth;
        final isLandscape =
            widget.settingsCache!.projectOrientation == "landscape";

        // Calculate preview size - max 400px wide for portrait, 500px for landscape
        final maxPreviewWidth = isLandscape ? 500.0 : 320.0;
        final previewWidth = availableWidth.clamp(200.0, maxPreviewWidth);
        final aspectRatioValue = outputImageLoader.getDisplayAspectRatio();
        final previewHeight = previewWidth * aspectRatioValue;

        final resolutionString = outputImageLoader.getResolutionString();

        return Column(
          children: [
            // Output settings chips - now above the preview
            _buildOutputSettingsChips(availableWidth),

            const SizedBox(height: 20),

            // Centered preview image
            Center(
              child: Column(
                children: [
                  Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: AppColors.settingsCardBorder,
                        width: 1,
                      ),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(7),
                      child: CustomPaint(
                        size: Size(previewWidth, previewHeight),
                        painter: outputImageLoader.guideImage == null
                            ? null
                            : GridPainterSE(
                                outputImageLoader.offsetX,
                                outputImageLoader.offsetY,
                                outputImageLoader.ghostImageOffsetX,
                                outputImageLoader.ghostImageOffsetY,
                                outputImageLoader.guideImage,
                                outputImageLoader.aspectRatio!,
                                outputImageLoader.projectOrientation!,
                                hideToolTip: true,
                                backgroundColor:
                                    outputImageLoader.backgroundColor,
                              ),
                      ),
                    ),
                  ),
                  if (resolutionString != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 8.0),
                      child: Text(
                        resolutionString,
                        style: TextStyle(
                          color: Colors.grey.shade500,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // Offset cards
            _buildOffsetCardsRow(availableWidth),
          ],
        );
      },
    );
  }

  String _getDateStampValue() {
    final cache = widget.settingsCache!;
    if (cache.exportDateStampEnabled) {
      return "On";
    } else if (cache.galleryDateLabelsEnabled) {
      return "Thumbnails";
    }
    return "Off";
  }

  Widget _buildOutputSettingsChips(double availableWidth) {
    final cache = widget.settingsCache!;

    final chips = [
      _OutputChip(label: "Framerate", value: "$framerate FPS"),
      _OutputChip(
        label: "Orientation",
        value: _capitalizeFirstLetter(cache.projectOrientation),
      ),
      _OutputChip(label: "Aspect", value: cache.aspectRatio),
      _OutputChip(
        label: "Stabilization",
        value: _capitalizeFirstLetter(cache.stabilizationMode),
      ),
      _OutputChip(
        label: "Watermark",
        value: cache.watermarkEnabled ? "On" : "Off",
      ),
      _OutputChip(
        label: "Date Stamp",
        value: _getDateStampValue(),
      ),
    ];

    // Wide layout: all chips in a single row
    if (availableWidth >= 700) {
      return Wrap(
        spacing: 8,
        runSpacing: 8,
        alignment: WrapAlignment.center,
        children: chips.map((chip) => _buildChipWidget(chip)).toList(),
      );
    }

    // Narrow layout: split into two rows of 3 chips each
    final firstRow = chips.sublist(0, 3);
    final secondRow = chips.sublist(3, 6);

    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: firstRow
              .map((chip) => Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: _buildChipWidget(chip),
                  ))
              .toList(),
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: secondRow
              .map((chip) => Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: _buildChipWidget(chip),
                  ))
              .toList(),
        ),
      ],
    );
  }

  Widget _buildChipWidget(_OutputChip chip) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.settingsCardBackground,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.settingsCardBorder, width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            chip.label,
            style: TextStyle(
              color: Colors.grey.shade500,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            chip.value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOffsetCardsRow(double availableWidth) {
    final offsetCards = [
      _buildCompactOffsetCard(
        title: "Eye Distance",
        value: outputImageLoader.offsetX * 2,
        subtitle: "of width",
        infoContent:
            'The spacing between the eye guide lines, shown as a percentage of the image width. Adjust in Settings → Eye Position.',
      ),
      _buildCompactOffsetCard(
        title: "Vertical Offset",
        value: outputImageLoader.offsetY,
        subtitle: "of height",
        infoContent:
            'How far down the eye guide line sits, shown as a percentage of the image height. Adjust in Settings → Eye Position.',
      ),
    ];

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        offsetCards[0],
        const SizedBox(width: 12),
        offsetCards[1],
      ],
    );
  }

  Widget _buildCompactOffsetCard({
    required String title,
    required double value,
    required String subtitle,
    String? infoContent,
  }) {
    final String roundedOffset = (value * 100).toStringAsFixed(1);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.settingsCardBackground,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.settingsCardBorder, width: 1),
      ),
      child: Column(
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                title,
                style: TextStyle(
                  color: Colors.grey.shade500,
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                ),
              ),
              if (infoContent != null) InfoTooltipIcon(content: infoContent),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            "$roundedOffset%",
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w600,
            ),
          ),
          Text(
            subtitle,
            style: TextStyle(
              color: Colors.grey.shade600,
              fontSize: 10,
            ),
          ),
        ],
      ),
    );
  }

  String _capitalizeFirstLetter(String input) {
    if (input.isEmpty) return input;
    return input[0].toUpperCase() + input.substring(1).toLowerCase();
  }

  int _determineStep() {
    if (widget.settingsCache!.noPhotos) return 1;
    if (!widget.settingsCache!.hasOpenedNonEmptyGallery) return 2;
    if (!widget.settingsCache!.hasSeenGuideModeTut &&
        widget.settingsCache!.hasTakenFirstPhoto) {
      return 3;
    }
    if (!widget.settingsCache!.hasTakenMoreThanOnePhoto) return 4;
    if (!widget.settingsCache!.hasViewedFirstVideo) return 5;
    return 0;
  }

  Widget dashboardWidget() {
    final cache = widget.settingsCache!;

    return LayoutBuilder(
      builder: (context, constraints) {
        final useWideLayout = constraints.maxWidth >= 700;

        final cards = [
          StatsCard(title: "Streak", value: cache.streak.toString()),
          StatsCard(
            title: "Photo today",
            value: widget.photoTakenToday ? "Yes" : "No",
          ),
          StatsCard(title: "Photos", value: cache.photoCount.toString()),
          StatsCard(
            title: "Timespan",
            value: "${cache.lengthInDays} days",
          ),
        ];

        if (useWideLayout) {
          return Row(
            children: [
              for (int i = 0; i < cards.length; i++) ...[
                Expanded(child: cards[i]),
                if (i < cards.length - 1) const SizedBox(width: 12.0),
              ],
            ],
          );
        }

        return Column(
          children: [
            Row(
              children: [
                Expanded(child: cards[0]),
                const SizedBox(width: 12.0),
                Expanded(child: cards[1]),
              ],
            ),
            const SizedBox(height: 12.0),
            Row(
              children: [
                Expanded(child: cards[2]),
                const SizedBox(width: 12.0),
                Expanded(child: cards[3]),
              ],
            ),
          ],
        );
      },
    );
  }
}

extension DateTimeExtension on DateTime {
  bool isSameDate(DateTime other) {
    return year == other.year && month == other.month && day == other.day;
  }
}

class CardBuilder extends StatelessWidget {
  final List<Widget> children;
  final EdgeInsetsGeometry padding;

  const CardBuilder({
    super.key,
    required this.children,
    this.padding = const EdgeInsets.all(16.0),
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: AppColors.settingsCardBackground,
        borderRadius: BorderRadius.circular(14.0),
        border: Border.all(color: AppColors.settingsCardBorder, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: children,
      ),
    );
  }
}

class TextRowBuilder extends StatelessWidget {
  final String title;
  final String value;
  final TextStyle? valueTextStyle;

  const TextRowBuilder({
    super.key,
    required this.title,
    required this.value,
    this.valueTextStyle,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            color: AppColors.settingsTextSecondary,
            fontSize: 13.7,
            height: 0.97,
          ),
        ),
        const SizedBox(height: 8.0),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              value,
              style: valueTextStyle ??
                  const TextStyle(
                    color: AppColors.settingsTextPrimary,
                    fontSize: 24.0,
                    fontWeight: FontWeight.bold,
                  ),
            ),
          ],
        ),
      ],
    );
  }
}

class StatsCard extends StatelessWidget {
  final String title;
  final String value;

  const StatsCard({super.key, required this.title, required this.value});

  @override
  Widget build(BuildContext context) {
    return CardBuilder(
      children: [TextRowBuilder(title: title, value: value)],
    );
  }
}

class SpecialCard extends StatelessWidget {
  final String projectOrientation;
  final String aspectRatio;
  final String resolution;
  final bool watermarkEnabled;
  final String stabilizationMode;
  final int framerate;

  const SpecialCard({
    super.key,
    required this.projectOrientation,
    required this.aspectRatio,
    required this.resolution,
    required this.watermarkEnabled,
    required this.stabilizationMode,
    required this.framerate,
  });

  @override
  Widget build(BuildContext context) {
    return CardBuilder(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
      children: [
        _buildSettingsRow("Framerate", "$framerate FPS"),
        _buildSettingsRow(
          "Orientation",
          _capitalizeFirstLetter(projectOrientation),
        ),
        _buildSettingsRow("Resolution", resolution),
        _buildSettingsRow("Aspect ratio", aspectRatio),
        _buildSettingsRow(
          "Stabilization",
          _capitalizeFirstLetter(stabilizationMode),
        ),
        _buildSettingsRow(
          "Watermark",
          watermarkEnabled ? "Yes" : "No",
          showDivider: false,
        ),
      ],
    );
  }

  Widget _buildSettingsRow(
    String title,
    String value, {
    bool showDivider = true,
  }) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 12.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(
                child: Text(
                  title,
                  style: const TextStyle(
                    color: AppColors.settingsTextPrimary,
                    fontSize: 13.0,
                    fontWeight: FontWeight.w400,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  value,
                  style: const TextStyle(
                    color: AppColors.settingsTextSecondary,
                    fontSize: 13.0,
                    fontWeight: FontWeight.w400,
                  ),
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.end,
                ),
              ),
            ],
          ),
        ),
        if (showDivider)
          const Divider(
            height: 1,
            thickness: 1,
            color: AppColors.settingsCardBorder,
          ),
      ],
    );
  }

  String _capitalizeFirstLetter(String input) {
    if (input.isEmpty) return input;
    return input[0].toUpperCase() + input.substring(1).toLowerCase();
  }
}

class _OutputChip {
  final String label;
  final String value;

  const _OutputChip({required this.label, required this.value});
}
