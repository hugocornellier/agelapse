import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as path;

import '../services/raw_decoder.dart';
import '../styles/styles.dart';
import '../utils/dir_utils.dart';
import '../utils/format_decode_utils.dart';

/// Displays an image file, decoding HEIC/AVIF/RAW formats on demand when the
/// current platform cannot render them natively.
class FormatAwareImage extends StatefulWidget {
  final File imageFile;
  final BoxFit fit;
  final Widget? errorWidget;

  const FormatAwareImage({
    super.key,
    required this.imageFile,
    this.fit = BoxFit.contain,
    this.errorWidget,
  });

  @override
  State<FormatAwareImage> createState() => _FormatAwareImageState();
}

class _FormatAwareImageState extends State<FormatAwareImage> {
  Future<Uint8List?>? _decodedBytesFuture;

  @override
  void initState() {
    super.initState();
    _refreshDecodeFuture();
  }

  @override
  void didUpdateWidget(covariant FormatAwareImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.imageFile.path != widget.imageFile.path) {
      _refreshDecodeFuture();
    }
  }

  void _refreshDecodeFuture() {
    _decodedBytesFuture = _needsPreviewDecode(widget.imageFile.path)
        ? _decodePreviewBytes(widget.imageFile.path)
        : null;
  }

  bool _needsPreviewDecode(String imagePath) {
    final extension = path.extension(imagePath).toLowerCase();

    if (extension == '.heic' || extension == '.heif') {
      return !(Platform.isMacOS || Platform.isIOS);
    }

    return extension == '.avif' || RawDecoder.isRawExtension(extension);
  }

  Future<Uint8List?> _decodePreviewBytes(String imagePath) async {
    final extension = path.extension(imagePath).toLowerCase();
    final tempDir = await DirUtils.getTemporaryDirPath();
    return FormatDecodeUtils.decodeToCvCompatibleBytes(
        imagePath, extension, tempDir);
  }

  Widget _buildErrorWidget() {
    return widget.errorWidget ?? Container(color: AppColors.overlay);
  }

  @override
  Widget build(BuildContext context) {
    if (_decodedBytesFuture == null) {
      return Image.file(
        widget.imageFile,
        fit: widget.fit,
        errorBuilder: (context, error, stack) => _buildErrorWidget(),
      );
    }

    return FutureBuilder<Uint8List?>(
      future: _decodedBytesFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator.adaptive());
        }

        final decodedBytes = snapshot.data;
        if (decodedBytes == null || decodedBytes.isEmpty) {
          return _buildErrorWidget();
        }

        return Image.memory(
          decodedBytes,
          fit: widget.fit,
          gaplessPlayback: true,
          errorBuilder: (context, error, stack) => _buildErrorWidget(),
        );
      },
    );
  }
}
