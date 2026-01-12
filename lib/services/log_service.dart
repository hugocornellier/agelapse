import 'dart:async';
import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path/path.dart' as path;
import 'package:share_plus/share_plus.dart';

import '../utils/dir_utils.dart';

// ignore_for_file: depend_on_referenced_packages, avoid_print

class LogService {
  static final LogService _instance = LogService._internal();
  static LogService get instance => _instance;

  static const int maxLogSizeBytes = 5 * 1024 * 1024; // 5 MB
  static const String _logFileName = 'agelapse.log';

  File? _logFile;
  IOSink? _sink;
  bool _initialized = false;

  LogService._internal();

  Future<void> initialize() async {
    if (_initialized) return;

    final appDir = await DirUtils.getAppDocumentsDirPath();
    final logPath = path.join(appDir, _logFileName);
    _logFile = File(logPath);

    // Create file if doesn't exist
    if (!await _logFile!.exists()) {
      await _logFile!.create(recursive: true);
    }

    // Check size and rotate if needed
    await _rotateIfNeeded();

    _sink = _logFile!.openWrite(mode: FileMode.append);
    _initialized = true;

    log('--- Log session started ---');
  }

  Future<void> _rotateIfNeeded() async {
    if (_logFile == null || !await _logFile!.exists()) return;

    final stat = await _logFile!.stat();
    if (stat.size >= maxLogSizeBytes) {
      // Keep last ~2.5MB of logs (half the max)
      final content = await _logFile!.readAsString();
      final halfPoint = content.length ~/ 2;

      // Find a newline near the halfway point to avoid cutting mid-line
      int cutPoint = content.indexOf('\n', halfPoint);
      if (cutPoint == -1) cutPoint = halfPoint;

      final trimmedContent = content.substring(cutPoint + 1);
      await _logFile!.writeAsString(
        '--- Log truncated (exceeded ${maxLogSizeBytes ~/ (1024 * 1024)}MB) ---\n$trimmedContent',
      );
    }
  }

  void log(String message) {
    final timestamp = DateTime.now().toIso8601String();
    final formattedMessage = '[$timestamp] $message';

    // Print to console in debug mode only (bypasses zone to avoid recursion)
    if (kDebugMode) {
      Zone.root.print(formattedMessage);
    }

    // Always write to file if initialized
    if (_initialized && _sink != null) {
      _sink!.writeln(formattedMessage);
    }
  }

  /// Called when app is closing
  Future<void> dispose() async {
    await _sink?.flush();
    await _sink?.close();
    _sink = null;
  }

  Future<String> getLogFilePath() async {
    if (_logFile == null) {
      final appDir = await DirUtils.getAppDocumentsDirPath();
      return path.join(appDir, _logFileName);
    }
    return _logFile!.path;
  }

  Future<String> getLogContent() async {
    final logPath = await getLogFilePath();
    final file = File(logPath);
    if (await file.exists()) {
      return await file.readAsString();
    }
    return 'No logs available.';
  }

  Future<void> exportLogs() async {
    await _sink?.flush();
    final logPath = await getLogFilePath();
    final file = File(logPath);

    if (await file.exists()) {
      final deviceInfo = await _getDeviceInfo();
      final logContent = await file.readAsString();
      final exportContent = '$deviceInfo\n$logContent';

      if (Platform.isWindows || Platform.isMacOS || Platform.isLinux) {
        // Desktop: Native save dialog
        final dateStr = DateFormat('yyyy-MM-dd').format(DateTime.now());
        final result = await FilePicker.platform.saveFile(
          dialogTitle: 'Save AgeLapse Logs',
          fileName: 'agelapse_logs_$dateStr.log',
          type: FileType.custom,
          allowedExtensions: ['log', 'txt'],
        );

        if (result != null) {
          await File(result).writeAsString(exportContent);
        }
      } else {
        // Mobile: Share dialog
        final exportPath = path.join(
          Directory.systemTemp.path,
          'agelapse_logs_${DateTime.now().millisecondsSinceEpoch}.log',
        );
        final exportFile = File(exportPath);
        await exportFile.writeAsString(exportContent);

        await SharePlus.instance.share(
          ShareParams(files: [XFile(exportPath)], subject: 'AgeLapse Logs'),
        );
      }
    }
  }

  Future<String> _getDeviceInfo() async {
    final sb = StringBuffer();
    sb.writeln('═══════════════════════════════════════');
    sb.writeln('           AGELAPSE LOG EXPORT          ');
    sb.writeln('═══════════════════════════════════════');
    sb.writeln('Exported: ${DateTime.now().toIso8601String()}');

    try {
      final packageInfo = await PackageInfo.fromPlatform();
      sb.writeln(
        'App Version: ${packageInfo.version} (${packageInfo.buildNumber})',
      );
    } catch (_) {}

    sb.writeln(
      'Platform: ${Platform.operatingSystem} ${Platform.operatingSystemVersion}',
    );

    try {
      final deviceInfo = DeviceInfoPlugin();
      if (Platform.isAndroid) {
        final info = await deviceInfo.androidInfo;
        sb.writeln('Device: ${info.manufacturer} ${info.model}');
        sb.writeln(
          'Android: ${info.version.release} (SDK ${info.version.sdkInt})',
        );
        sb.writeln('Supported ABIs: ${info.supportedAbis.join(', ')}');
      } else if (Platform.isIOS) {
        final info = await deviceInfo.iosInfo;
        sb.writeln('Device: ${info.utsname.machine}');
        sb.writeln('iOS: ${info.systemVersion}');
        sb.writeln('Model: ${info.model}');
      } else if (Platform.isMacOS) {
        final info = await deviceInfo.macOsInfo;
        sb.writeln('Device: ${info.model}');
        sb.writeln('macOS: ${info.osRelease}');
        sb.writeln('Arch: ${info.arch}');
      } else if (Platform.isWindows) {
        final info = await deviceInfo.windowsInfo;
        sb.writeln('Computer: ${info.computerName}');
        sb.writeln('Windows: ${info.productName}');
        sb.writeln('Build: ${info.buildNumber}');
      } else if (Platform.isLinux) {
        final info = await deviceInfo.linuxInfo;
        sb.writeln('Distro: ${info.prettyName}');
      }
    } catch (_) {}

    sb.writeln('═══════════════════════════════════════');
    sb.writeln('');
    return sb.toString();
  }

  Future<void> clearLogs() async {
    await _sink?.flush();
    await _sink?.close();

    if (_logFile != null && await _logFile!.exists()) {
      await _logFile!.writeAsString('');
    }

    _sink = _logFile!.openWrite(mode: FileMode.append);
    log('--- Logs cleared ---');
  }

  /// Creates a Zone that captures print statements
  static R runWithLogging<R>(R Function() body) {
    return runZoned(
      body,
      zoneSpecification: ZoneSpecification(
        print: (Zone self, ZoneDelegate parent, Zone zone, String line) {
          // Still print to console
          parent.print(zone, line);
          // Also log to file
          if (_instance._initialized) {
            _instance.log(line);
          }
        },
      ),
    );
  }
}
