import 'dart:async';
import 'dart:convert';
import 'dart:io';

const _sqliteVersion = '3.5.0';
const _sqliteReleaseBase =
    'https://github.com/simolus3/sqlite3.dart/releases/download/'
    'sqlite3-$_sqliteVersion';
const _liteRtReleaseBase =
    'https://github.com/hugocornellier/flutter_litert/releases/download/'
    'litert-desktop-gpu-v1.0.0';

final class _Artifact {
  const _Artifact({
    required this.sourceName,
    required this.sha256Hash,
    required this.url,
    required this.destination,
  });

  final String sourceName;
  final String sha256Hash;
  final Uri url;
  final File destination;
}

Future<void> main(List<String> arguments) async {
  if (arguments.length != 3) {
    stderr.writeln(
      'Usage: dart tool/prefetch_native_artifacts.dart '
      '<android|ios|linux|macos|windows> <cache-directory> '
      '<project-directory>',
    );
    exitCode = 64;
    return;
  }

  final target = arguments[0];
  final cacheDirectory = Directory(arguments[1]).absolute;
  final projectDirectory = Directory(arguments[2]).absolute;
  final supportedTargets = {'android', 'ios', 'linux', 'macos', 'windows'};
  if (!supportedTargets.contains(target)) {
    stderr.writeln('Unsupported native-artifact target: $target');
    exitCode = 64;
    return;
  }

  final sqliteRoot = _packageRoot(projectDirectory, 'sqlite3', _sqliteVersion);
  final artifacts = <_Artifact>[
    ..._sqliteArtifacts(projectDirectory, target),
    if (target == 'linux' || target == 'windows')
      ..._liteRtArtifacts(
        target,
        _packageRoot(projectDirectory, 'flutter_litert', '3.8.0'),
      ),
  ];

  stdout.writeln(
    'Preparing ${artifacts.length} verified native artifacts for $target '
    '(sqlite3 package: ${sqliteRoot.path}).',
  );
  for (final artifact in artifacts) {
    final cached = await _obtainArtifact(artifact, cacheDirectory);
    await _installArtifact(cached, artifact);
  }
}

Directory _packageRoot(
  Directory projectDirectory,
  String packageName,
  String expectedVersion,
) {
  final packageConfig = File.fromUri(
    projectDirectory.uri.resolve('.dart_tool/package_config.json'),
  );
  if (!packageConfig.existsSync()) {
    throw StateError(
      '${packageConfig.path} does not exist. Run flutter pub get first.',
    );
  }

  final config = jsonDecode(packageConfig.readAsStringSync());
  final packages = (config as Map<String, Object?>)['packages']! as List;
  final package = packages.cast<Map<String, Object?>>().singleWhere(
    (entry) => entry['name'] == packageName,
    orElse: () => throw StateError(
      'Package $packageName is missing from ${packageConfig.path}.',
    ),
  );
  final root = Directory.fromUri(
    packageConfig.uri.resolve(package['rootUri']! as String),
  );
  final normalizedPath = root.path.replaceAll('\\', '/');
  if (!normalizedPath.endsWith('/$packageName-$expectedVersion')) {
    throw StateError(
      'The native-artifact manifest expects $packageName $expectedVersion, '
      'but package_config.json resolves it to ${root.path}. Update the '
      'manifest and its checksums with the dependency.',
    );
  }
  return root;
}

Iterable<_Artifact> _sqliteArtifacts(
  Directory projectDirectory,
  String target,
) sync* {
  final sharedBuild = Directory.fromUri(
    projectDirectory.uri.resolve(
      '.dart_tool/hooks_runner/shared/sqlite3/build/',
    ),
  );

  final specs = switch (target) {
    'android' => const [
      (
        'libsqlite3.arm.android.so',
        '6c1b8dffc1ddefaf02e771711491410bc3ab1db858d3d23d2925e0b2cd691b93',
        'libsqlite3.so',
      ),
      (
        'libsqlite3.arm64.android.so',
        'e99515af1d7119fb61843ae5e597344e7f258563de3a7e5a3869f627aab2887b',
        'libsqlite3.so',
      ),
      (
        'libsqlite3.x64.android.so',
        'e5a2d46ac5e11f471e1aaedfd364f54c7961a6900432d289ea3f5781bcaaf4cd',
        'libsqlite3.so',
      ),
    ],
    'ios' => const [
      (
        'libsqlite3.arm64.ios.dylib',
        '14ddadc35d7e92e58e219a34dc4a9b66fd5b195c9e144dcfed06978a65dfaba9',
        'libsqlite3.dylib',
      ),
      (
        'libsqlite3.arm64.ios_sim.dylib',
        '1ef1f54d5524f6c99ff74ae1244fb3d815f7a40c7c1cf7615a6321ba752fa8ff',
        'libsqlite3.dylib',
      ),
      (
        'libsqlite3.x64.ios_sim.dylib',
        '757f5d6e3892d04826aa531604f182f4489825039343952d60bb5eb506b09a80',
        'libsqlite3.dylib',
      ),
    ],
    'linux' => const [
      (
        'libsqlite3.x64.linux.so',
        '2219febf70a5ed39a39db1bc46e00d3df0b3bb881ad36a67e2e5a0cd91ebd3a5',
        'libsqlite3.so',
      ),
    ],
    'macos' => const [
      (
        'libsqlite3.arm64.macos.dylib',
        'f84bea51f2498dea33564d854def1252ec4551d34371545a505589b361efe487',
        'libsqlite3.dylib',
      ),
      (
        'libsqlite3.x64.macos.dylib',
        'bd96fb2480c0f62b72dd5cb3b5c4acf61809cce7e07019fbe8346ba9972d75c1',
        'libsqlite3.dylib',
      ),
    ],
    'windows' => const [
      (
        'sqlite3.x64.windows.dll',
        '858141a2826f53e8374cb07de2638e0f1ac944f49b897dd558feba5597e86d1c',
        'sqlite3.dll',
      ),
    ],
    _ => throw ArgumentError.value(target, 'target'),
  };

  for (final spec in specs) {
    final (sourceName, hash, installedName) = spec;
    final destinationDirectory = Directory.fromUri(
      sharedBuild.uri.resolve('download-${hash.substring(0, 8)}/'),
    );
    yield _Artifact(
      sourceName: sourceName,
      sha256Hash: hash,
      url: Uri.parse('$_sqliteReleaseBase/$sourceName'),
      destination: File.fromUri(
        destinationDirectory.uri.resolve(installedName),
      ),
    );
  }
}

Iterable<_Artifact> _liteRtArtifacts(
  String target,
  Directory packageRoot,
) sync* {
  final specs = switch (target) {
    'linux' => const [
      (
        'libLiteRtWebGpuAccelerator.so',
        'd732c738e5206dd3374d0496a3f00deb4e02aec37bf5678c5617bad422bb0249',
        'linux/lib/libLiteRtWebGpuAccelerator.so',
      ),
    ],
    'windows' => const [
      (
        'libLiteRtWebGpuAccelerator.dll',
        '65fb92e4b0c3f1bba389964ffac5544bfebe5edf029c5a94a87864fa3e3ee124',
        'windows/libLiteRtWebGpuAccelerator.dll',
      ),
      (
        'dxcompiler.dll',
        '9b5e10ed756c461b4ec2c83a99f1d6ace20e97826e9c0b0e966b7b1cd6f2aec6',
        'windows/dxcompiler.dll',
      ),
      (
        'dxil.dll',
        'cbcfe883a09fd0ca1f98abdf3a9553b560895e3283a136da82a8381253a169df',
        'windows/dxil.dll',
      ),
    ],
    _ => throw ArgumentError.value(target, 'target'),
  };

  for (final spec in specs) {
    final (sourceName, hash, destinationPath) = spec;
    yield _Artifact(
      sourceName: sourceName,
      sha256Hash: hash,
      url: Uri.parse('$_liteRtReleaseBase/$sourceName'),
      destination: File.fromUri(packageRoot.uri.resolve(destinationPath)),
    );
  }
}

Future<File> _obtainArtifact(
  _Artifact artifact,
  Directory cacheDirectory,
) async {
  final contentDirectory = Directory.fromUri(
    cacheDirectory.uri.resolve('${artifact.sha256Hash}/'),
  );
  await contentDirectory.create(recursive: true);
  final cached = File.fromUri(
    contentDirectory.uri.resolve(artifact.sourceName),
  );
  if (await _hasExpectedHash(cached, artifact.sha256Hash)) {
    stdout.writeln('Native artifact cache hit: ${artifact.sourceName}');
    return cached;
  }

  if (await cached.exists()) {
    await cached.delete();
  }
  final temporary = File('${cached.path}.tmp');
  Object? lastError;
  for (var attempt = 1; attempt <= 6; attempt++) {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 30)
      ..idleTimeout = const Duration(seconds: 60);
    try {
      if (await temporary.exists()) {
        await temporary.delete();
      }
      stdout.writeln('Downloading ${artifact.url} (attempt $attempt of 6)...');
      final request = await client.getUrl(artifact.url);
      request.headers.set(
        HttpHeaders.userAgentHeader,
        'AgeLapse-CI-native-artifact-prefetch',
      );
      final response = await request.close().timeout(
        const Duration(seconds: 60),
      );
      if (response.statusCode != HttpStatus.ok) {
        await response.drain<void>();
        throw HttpException(
          'HTTP ${response.statusCode} ${response.reasonPhrase}',
          uri: artifact.url,
        );
      }
      await response
          .pipe(temporary.openWrite())
          .timeout(const Duration(minutes: 5));
      if (!await _hasExpectedHash(temporary, artifact.sha256Hash)) {
        throw StateError('SHA-256 mismatch for ${artifact.sourceName}.');
      }
      await temporary.rename(cached.path);
      return cached;
    } catch (error) {
      lastError = error;
      stderr.writeln(
        'Attempt $attempt failed for ${artifact.sourceName}: $error',
      );
      if (await temporary.exists()) {
        await temporary.delete();
      }
      if (attempt < 6) {
        await Future<void>.delayed(Duration(seconds: 1 << attempt));
      }
    } finally {
      client.close(force: true);
    }
  }

  throw StateError(
    'Could not fetch ${artifact.sourceName} after 6 attempts: $lastError',
  );
}

Future<void> _installArtifact(File cached, _Artifact artifact) async {
  if (await _hasExpectedHash(artifact.destination, artifact.sha256Hash)) {
    stdout.writeln('Native artifact already installed: ${artifact.sourceName}');
    return;
  }

  await artifact.destination.parent.create(recursive: true);
  final temporary = File('${artifact.destination.path}.tmp');
  if (await temporary.exists()) {
    await temporary.delete();
  }
  await cached.copy(temporary.path);
  if (await artifact.destination.exists()) {
    await artifact.destination.delete();
  }
  await temporary.rename(artifact.destination.path);
  stdout.writeln(
    'Installed ${artifact.sourceName} at ${artifact.destination.path}',
  );
}

Future<bool> _hasExpectedHash(File file, String expected) async {
  if (!await file.exists()) {
    return false;
  }

  final ProcessResult result;
  if (Platform.isWindows) {
    result = await Process.run('certutil', ['-hashfile', file.path, 'SHA256']);
  } else if (Platform.isMacOS) {
    result = await Process.run('shasum', ['-a', '256', file.path]);
  } else {
    result = await Process.run('sha256sum', [file.path]);
  }
  if (result.exitCode != 0) {
    throw ProcessException(
      Platform.isWindows
          ? 'certutil'
          : Platform.isMacOS
          ? 'shasum'
          : 'sha256sum',
      [file.path],
      result.stderr.toString(),
      result.exitCode,
    );
  }

  final output = result.stdout.toString().toLowerCase();
  return RegExp(r'\b[a-f0-9]{64}\b').firstMatch(output)?.group(0) == expected;
}
