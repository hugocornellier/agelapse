import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../services/settings_cache.dart';
import '../services/stab_update_event.dart';
import '../styles/styles.dart';
import '../utils/settings_utils.dart';
import '../utils/utils.dart';
import '../widgets/fancy_button.dart';
import '../widgets/grid_painter_se.dart';
import '../widgets/settings_sheet.dart';
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

  Future<bool> _waitForCache(
      {Duration timeout = const Duration(seconds: 30)}) async {
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
        body: Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    final cache = widget.settingsCache!;
    final bool isDesktop = _isDesktop;

    if (!isDesktop) {
      return Scaffold(
        backgroundColor: const Color(0xff0F0F0F),
        body: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16.0),
                      child: cache.noPhotos ||
                              !cache.hasOpenedNonEmptyGallery ||
                              !cache.hasTakenMoreThanOnePhoto ||
                              !cache.hasViewedFirstVideo
                          ? _buildNoPhotosContent(context, includeOutput: true)
                          : _buildDashboardContent(),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xff0F0F0F),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final double rightPaneWidth =
              (constraints.maxWidth * 0.42).clamp(480.0, 840.0);

          final double leftMaxWidth =
              (constraints.maxWidth - rightPaneWidth - 1).clamp(800.0, 1160.0);

          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: SingleChildScrollView(
                  child: Center(
                    child: ConstrainedBox(
                      constraints: BoxConstraints(maxWidth: leftMaxWidth),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16.0),
                        child: cache.noPhotos ||
                                !cache.hasOpenedNonEmptyGallery ||
                                !cache.hasTakenMoreThanOnePhoto ||
                                !cache.hasViewedFirstVideo
                            ? _buildNoPhotosContent(context,
                                includeOutput: false)
                            : _buildDashboardSection(includeOutput: false),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(
                width: 1,
                child: VerticalDivider(
                  width: 1,
                  thickness: 1,
                  color: Color(0xff1E1E1E),
                ),
              ),
              SizedBox(
                width: rightPaneWidth,
                child: SingleChildScrollView(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16.0),
                    child: _buildOutputSectionForWidth(rightPaneWidth - 32.0),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildNoPhotosContent(BuildContext context,
      {bool includeOutput = true}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const SizedBox(height: 30),
        _buildSectionTitle('Getting started', ''),
        const SizedBox(height: 21),
        ..._buildStepButtons(context, _determineStep()),
        const SizedBox(height: 40),
        _buildDashboardSection(includeOutput: includeOutput),
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
        buildFancyButton(
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
        ),
        const SizedBox(height: 16),
        const Row(
          children: <Widget>[
            SizedBox(width: 8),
            Expanded(
              child: Divider(
                height: 0.8,
              ),
            ),
            SizedBox(width: 8),
            Text(
              "OR",
              style: TextStyle(color: Colors.grey, fontSize: 11),
            ),
            SizedBox(width: 8),
            Expanded(
              child: Divider(
                height: 0.8,
              ),
            ),
            SizedBox(width: 8),
          ],
        ),
        const SizedBox(height: 16),
        buildFancyButton(
          text: 'Import photo(s)',
          icon: Icons.file_upload,
          onPressed: () async {
            await widget.setUserOnImportTutorialTrue();
            widget.goToPage(1);
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
              Icon(
                icon,
                size: 18,
                color: AppColors.settingsTextSecondary,
              ),
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
            ],
          ),
          if (title == 'Output')
            GestureDetector(
              onTap: () => _openSettings(context),
              child: Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: AppColors.settingsCardBorder,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.tune,
                  size: 18,
                  color: AppColors.settingsTextSecondary,
                ),
              ),
            ),
        ],
      ),
    );
  }

  bool get _isDesktop {
    if (kIsWeb) return false;
    final platform = defaultTargetPlatform;
    return platform == TargetPlatform.macOS ||
        platform == TargetPlatform.windows ||
        platform == TargetPlatform.linux;
  }

  void _openSettings(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        return SettingsSheet(
          projectId: widget.projectId,
          onlyShowVideoSettings: true,
          cancelStabCallback: widget.cancelStabCallback,
          stabCallback: widget.stabCallback,
          refreshSettings: widget.refreshSettings,
          clearRawAndStabPhotos: widget.clearRawAndStabPhotos,
        );
      },
    );
  }

  Widget _buildDashboardSection({bool includeOutput = true}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (!widget.settingsCache!.noPhotos) ...[const SizedBox(height: 30)],
        _buildSectionTitle('Dashboard', ''),
        const SizedBox(height: 21),
        dashboardWidget(),
        const SizedBox(height: 30),
        if (includeOutput) _buildOutputSection(),
      ],
    );
  }

  Widget _buildOutputSectionForWidth(double availableWidth) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 30),
        _buildSectionTitle('Output', ''),
        const SizedBox(height: 21),
        _buildOutputContentForWidth(availableWidth),
        const SizedBox(height: 64),
      ],
    );
  }

  Widget _buildOutputContentForWidth(double paneWidth) {
    final isLandscape = widget.settingsCache!.projectOrientation == "landscape";
    final double sideLength = paneWidth * (isLandscape ? 0.5 : 0.43);
    final double landscapeCardWidth = (sideLength - 8.0) / 2;

    return Column(
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildImageAndOffsetCards(
              sideLength: sideLength,
              landscapeCardWidth: landscapeCardWidth,
              isLandscape: isLandscape,
            ),
            const SizedBox(width: 16.0),
            Flexible(
              child: SpecialCard(
                projectOrientation: widget.settingsCache!.projectOrientation,
                aspectRatio: widget.settingsCache!.aspectRatio,
                resolution: widget.settingsCache!.resolution,
                watermarkEnabled: widget.settingsCache!.watermarkEnabled,
                stabilizationMode: widget.settingsCache!.stabilizationMode,
                framerate: framerate,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildOutputSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.start,
      children: [
        const SizedBox(height: 30),
        _buildSectionTitle('Output', ''),
        const SizedBox(height: 21),
        _buildOutputContent(),
        const SizedBox(height: 64)
      ],
    );
  }

  Widget _buildOutputContent() {
    final screenWidth = MediaQuery.of(context).size.width;

    final isLandscape = widget.settingsCache!.projectOrientation == "landscape";
    final double sideLength = screenWidth * (isLandscape ? 0.5 : 0.43);
    final double landscapeCardWidth = (sideLength - 8.0) / 2;

    return Column(
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildImageAndOffsetCards(
              sideLength: sideLength,
              landscapeCardWidth: landscapeCardWidth,
              isLandscape: isLandscape,
            ),
            const SizedBox(width: 16.0),
            Flexible(
              child: SpecialCard(
                projectOrientation: widget.settingsCache!.projectOrientation,
                aspectRatio: widget.settingsCache!.aspectRatio,
                resolution: widget.settingsCache!.resolution,
                watermarkEnabled: widget.settingsCache!.watermarkEnabled,
                stabilizationMode: widget.settingsCache!.stabilizationMode,
                framerate: framerate,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildImageAndOffsetCards({
    required double sideLength,
    required double landscapeCardWidth,
    required bool isLandscape,
  }) {
    Map<String, double> aspectRatios = {
      "4:3": isLandscape ? 3 / 4 : 4 / 3,
      "16:9": isLandscape ? 9 / 16 : 16 / 9,
    };

    return Column(
      children: [
        CustomPaint(
          size: Size(sideLength,
              aspectRatios[outputImageLoader.aspectRatio]! * sideLength),
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
                  hideToolTip: true),
        ),
        const SizedBox(height: 12.0),
        Row(
          children: [
            _buildOffsetCard(
              title: "Inter-Eye\nDistance",
              value: outputImageLoader.offsetX * 2,
              width: isLandscape ? landscapeCardWidth : null,
            ),
            const SizedBox(width: 8.0),
            _buildOffsetCard(
              title: "Vertical\nOffset",
              value: outputImageLoader.offsetY,
              width: isLandscape ? landscapeCardWidth : null,
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildOffsetCard({
    required String title,
    required double value,
    double? width,
    int maxDecimalPlaces = 1,
    double fontSize = 17.5,
  }) {
    final String roundedOffset =
        (value * 100).toStringAsFixed(maxDecimalPlaces);

    return SizedBox(
      width: width,
      child: CardBuilder(
        padding: title == "Inter-Eye\nDistance" || title == "Vertical\nOffset"
            ? const EdgeInsets.all(12.0)
            : const EdgeInsets.all(16.0),
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  color: Colors.grey,
                  fontSize: 13,
                  height: 0.99,
                ),
              ),
              const SizedBox(height: 8.0),
              Column(
                children: [
                  Text(
                    "${roundedOffset.trim()} %",
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: fontSize,
                      fontWeight: FontWeight.normal,
                    ),
                  ),
                  Text(
                    title == "Inter-Eye\nDistance"
                        ? 'of image width'
                        : 'of image height',
                    style: const TextStyle(
                      color: Colors.grey, // Change this line
                      fontSize: 7, // Very tiny text
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
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
    return Column(
      mainAxisAlignment: MainAxisAlignment.start,
      children: [
        Row(
          children: [
            Flexible(
              child: StatsCard(
                title: "Streak",
                value: cache.streak.toString(),
              ),
            ),
            const SizedBox(width: 16.0),
            Flexible(
              child: StatsCard(
                title: "Photo taken today",
                value: widget.photoTakenToday ? "Yes" : "No",
              ),
            ),
          ],
        ),
        const SizedBox(height: 16.0),
        Row(
          children: [
            Flexible(
              child: StatsCard(
                title: "Photos",
                value: cache.photoCount.toString(),
              ),
            ),
            const SizedBox(width: 16.0),
            Flexible(
              child: StatsCard(
                title: "Timespan (days)",
                value: cache.lengthInDays.toString(),
              ),
            ),
          ],
        ),
      ],
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
        border: Border.all(
          color: AppColors.settingsCardBorder,
          width: 1,
        ),
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
      children: [
        TextRowBuilder(
          title: title,
          value: value,
        ),
      ],
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
            "Orientation", _capitalizeFirstLetter(projectOrientation)),
        _buildSettingsRow("Resolution", resolution),
        _buildSettingsRow("Aspect ratio", aspectRatio),
        _buildSettingsRow(
            "Stabilization", _capitalizeFirstLetter(stabilizationMode)),
        _buildSettingsRow("Watermark", watermarkEnabled ? "Yes" : "No",
            showDivider: false),
      ],
    );
  }

  Widget _buildSettingsRow(String title, String value,
      {bool showDivider = true}) {
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
