<div align="center">

# FFmpegKit for Flutter. Full-GPL version.

_Fork of the original FFmpeg Kit library to work with Android V2 bindings and Flutter 3+_

<p align="center">
  <a href="https://pub.dev/packages/ffmpeg_kit_flutter_new">
     <img src="https://img.shields.io/badge/pub-4.1.0-blue?logo=dart" alt="pub">
  </a>
  <a href="https://discord.gg/8NVwykjA">
    <img src="https://img.shields.io/discord/1387108888452665427?logo=discord&logoColor=white&label=Join+Us&color=blueviolet" alt="Discord">
  </a>
  <a href="https://buymeacoffee.com/sk3llo" target="_blank"><img src="https://cdn.buymeacoffee.com/buttons/default-orange.png" alt="Buy Me A Coffee" height="21" width="114"></a>
</p>
</div>

## Upgraded version of the original [Flutter FFmpegKit](https://github.com/arthenica/ffmpeg-kit/tree/main/flutter/flutter).

### 1. Features

- **Updated Bindings**: Updated Android and macOS bindings to work with the newest Flutter version

- **Includes**: Both `FFmpeg` and `FFprobe`

- **Supported Platforms**:
    - `Android`
    - `iOS`
    - `macOS`

- **FFmpeg Version**: `v8.0.0`

- **iOS and macOS Support**: iOS and macOS `Videotoolbox` support

- **Supported Architectures**:
    - **Android**:
        - `arm-v7a`
        - `arm-v7a-neon`
        - `arm64-v8a`
        - `x86`
        - `x86_64`
        - Requires `Android API Level 24` or later
        - Requires **Kotlin** `1.8.22` or later
    - **iOS**:
        - `armv7`
        - `armv7s`
        - `arm64`
        - `arm64-simulator`
        - `i386`
        - `x86_64`
        - `x86_64-mac-catalyst`
        - `arm64-mac-catalyst`
        - Requires `iOS SDK 14.0` or later
    - **macOS**:
        - `arm64`
        - `x86_64`
        - Requires `macOS SDK 10.15` or later

- **Storage Access**: Can process Storage Access Framework (SAF) Uris on Android

- **External Libraries**: 25 external libraries: `dav1d`, `fontconfig`, `freetype`, `fribidi`, `gmp`, `gnutls`, `kvazaar`, `lame`, `libass`, `libiconv`, `libilbc`, `libtheora`, `libvorbis`, `libvpx`, `libwebp`, `libxml2`, `opencore-amr`, `opus`, `shine`, `snappy`, `soxr`, `speex`, `twolame`, `vo-amrwbenc`, `zimg`

- **GPL Licensed Libraries**: 4 external libraries with GPL license: `vid.stab`, `x264`, `x265`, `xvidcore`

- **License**: Licensed under `LGPL 3.0` by default, some packages licensed by `GPL v3.0` effectively



### 2. Installation

Add `ffmpeg_kit_flutter_new` as a dependency in your `pubspec.yaml file`.

```yaml
dependencies:  
 ffmpeg_kit_flutter_new: ^4.1.0
```


### 3. Packages

There are eight different `ffmpeg-kit` packages:

| Package Name                                                           | Description                                                                                                   
|------------------------------------------------------------------------|-----------------------------------------------
| [Minimal](https://pub.dev/packages/ffmpeg_kit_flutter_new_min)         | A minimal version of FFmpeg Kit                |
| [Minimal-GPL](https://pub.dev/packages/ffmpeg_kit_flutter_new_min_gpl) | Minimal version with GPL licensing           
| [HTTPS](https://pub.dev/packages/ffmpeg_kit_flutter_new_https)         | FFmpeg Kit with HTTPS support                      |
| [HTTPS-GPL](https://pub.dev/packages/ffmpeg_kit_flutter_new_https_gpl) | HTTPS version with GPL licensing               |
| [Audio](https://pub.dev/packages/ffmpeg_kit_flutter_new_audio)         | FFmpeg Kit focused on audio processing            |
| [Video](https://pub.dev/packages/ffmpeg_kit_flutter_new_video)         | FFmpeg Kit focused on video processing                                                                        |
| [Full](https://pub.dev/packages/ffmpeg_kit_flutter_new_full)           | Full version of FFmpeg Kit                                                                                     |
| [Full-GPL](https://pub.dev/packages/ffmpeg_kit_flutter_new)            | Full version with GPL licensing  

Below you can see which system libraries and external libraries are enabled in each one of them.

Please remember that some parts of `FFmpeg` are licensed under the `GPL` and only `GPL` licensed `ffmpeg-kit` packages
include them.

<table>
<thead>
<tr>
<th align="center"></th>
<th align="center"><sup>min</sup></th>
<th align="center"><sup>min-gpl</sup></th>
<th align="center"><sup>https</sup></th>
<th align="center"><sup>https-gpl</sup></th>
<th align="center"><sup>audio</sup></th>
<th align="center"><sup>video</sup></th>
<th align="center"><sup>full</sup></th>
<th align="center"><sup>full-gpl</sup></th>
</tr>
</thead>
<tbody>
<tr>
<td align="center"><sup>external libraries</sup></td>
<td align="center">-</td>
<td align="center"><sup>vid.stab</sup><br><sup>x264</sup><br><sup>x265</sup><br><sup>xvidcore</sup></td>
<td align="center"><sup>gmp</sup><br><sup>gnutls</sup></td>
<td align="center"><sup>gmp</sup><br><sup>gnutls</sup><br><sup>vid.stab</sup><br><sup>x264</sup><br><sup>x265</sup><br><sup>xvidcore</sup></td>
<td align="center"><sup>lame</sup><br><sup>libilbc</sup><br><sup>libvorbis</sup><br><sup>opencore-amr</sup><br><sup>opus</sup><br><sup>shine</sup><br><sup>soxr</sup><br><sup>speex</sup><br><sup>twolame</sup><br><sup>vo-amrwbenc</sup></td>
<td align="center"><sup>dav1d</sup><br><sup>fontconfig</sup><br><sup>freetype</sup><br><sup>fribidi</sup><br><sup>kvazaar</sup><br><sup>libass</sup><br><sup>libiconv</sup><br><sup>libtheora</sup><br><sup>libvpx</sup><br><sup>libwebp</sup><br><sup>snappy</sup><br><sup>zimg</sup></td>
<td align="center"><sup>dav1d</sup><br><sup>fontconfig</sup><br><sup>freetype</sup><br><sup>fribidi</sup><br><sup>gmp</sup><br><sup>gnutls</sup><br><sup>kvazaar</sup><br><sup>lame</sup><br><sup>libass</sup><br><sup>libiconv</sup><br><sup>libilbc</sup><br><sup>libtheora</sup><br><sup>libvorbis</sup><br><sup>libvpx</sup><br><sup>libwebp</sup><br><sup>libxml2</sup><br><sup>opencore-amr</sup><br><sup>opus</sup><br><sup>shine</sup><br><sup>snappy</sup><br><sup>soxr</sup><br><sup>speex</sup><br><sup>twolame</sup><br><sup>vo-amrwbenc</sup><br><sup>zimg</sup></td>
<td align="center"><sup>dav1d</sup><br><sup>fontconfig</sup><br><sup>freetype</sup><br><sup>fribidi</sup><br><sup>gmp</sup><br><sup>gnutls</sup><br><sup>kvazaar</sup><br><sup>lame</sup><br><sup>libass</sup><br><sup>libiconv</sup><br><sup>libilbc</sup><br><sup>libtheora</sup><br><sup>libvorbis</sup><br><sup>libvpx</sup><br><sup>libwebp</sup><br><sup>libxml2</sup><br><sup>opencore-amr</sup><br><sup>opus</sup><br><sup>shine</sup><br><sup>snappy</sup><br><sup>soxr</sup><br><sup>speex</sup><br><sup>twolame</sup><br><sup>vid.stab</sup><br><sup>vo-amrwbenc</sup><br><sup>x264</sup><br><sup>x265</sup><br><sup>xvidcore</sup><br><sup>zimg</sup></td>
</tr>
<tr>
<td align="center"><sup>android system libraries</sup></td>
<td align="center" colspan=8><sup>zlib</sup><br><sup>MediaCodec</sup></td>
</tr>
<tr>
<td align="center"><sup>ios system libraries</sup></td>
<td align="center" colspan=8><sup>bzip2</sup><br><sup>AudioToolbox</sup><br><sup>AVFoundation</sup><br><sup>iconv</sup><br><sup>VideoToolbox</sup><br><sup>zlib</sup></td>
</tr>
<tr>
<tr>
<td align="center"><sup>macos system libraries</sup></td>
<td align="center" colspan=8><sup>bzip2</sup><br><sup>AudioToolbox</sup><br><sup>AVFoundation</sup><br><sup>Core Image</sup><br><sup>iconv</sup><br><sup>OpenCL</sup><br><sup>OpenGL</sup><br><sup>VideoToolbox</sup><br><sup>zlib</sup></td>
</tr>
<tr>
<td align="center"><sup>tvos system libraries</sup></td>
<td align="center" colspan=8><sup>bzip2</sup><br><sup>AudioToolbox</sup><br><sup>iconv</sup><br><sup>VideoToolbox</sup><br><sup>zlib</sup></td>
</tr>
</tbody>
</table>


### 4. Platform Support

The following table shows Android API level, iOS deployment target and macOS deployment target requirements in  
`ffmpeg_kit_flutter_new` releases.

<table align="center">  
  <thead>  
    <tr>  
      <th align="center">Android<br>API Level</th>  
      <th align="center">Kotlin<br>Minimum Version</th>  
      <th align="center">iOS Minimum<br>Deployment Target</th>  
      <th align="center">macOS Minimum<br>Deployment Target</th>  
    </tr>  
  </thead>  
  <tbody>  
    <tr>  
      <td align="center">24</td>  
      <td align="center">1.8.22</td>  
      <td align="center">14</td>  
      <td align="center">10.15</td>  
    </tr>  
  </tbody>  
</table>  

### 5. Using

1. Execute FFmpeg commands.

```dart  
import 'package:ffmpeg_kit_flutter/ffmpeg_kit.dart';

FFmpegKit.execute('-i file1.mp4 -c:v mpeg4 file2.mp4').then((session) async {
    final returnCode = await session.getReturnCode();  
    if (ReturnCode.isSuccess(returnCode)) {  
        // SUCCESS  
    } else if (ReturnCode.isCancel(returnCode)) {  
        // CANCEL  
    } else {
        // ERROR  
    }
});
```  

Or execute FFmpeg commands with a custom log callback.

```dart
import 'package:ffmpeg_kit_flutter/ffmpeg_kit.dart';
final outputPath = 'file2.mp4';

FFmpegKit.execute('-i file1.mp4 -c:v mpeg4 file2.mp4').thenReturnResultOrLogs(
    (_) => outputPath,
).then((result) => print('FFmpeg command executed successfully: $result'))
  .catchError((error) => print('FFmpeg command failed with error: $error'));
```
2. Each `execute` call creates a new session. Access every detail about your execution from the session created.  
  
```dart  
FFmpegKit.execute('-i file1.mp4 -c:v mpeg4 file2.mp4').then((session) async {  
    // Unique session id created for this execution
    final sessionId = session.getSessionId();  
    // Command arguments as a single string
    final command = session.getCommand();  
    // Command arguments
    final commandArguments = session.getArguments();  
    // State of the execution. Shows whether it is still running or completed
    final state = await session.getState();  
    // Return code for completed sessions. Will be undefined if session is still running or FFmpegKit fails to run it
    final returnCode = await session.getReturnCode();  
    final startTime = session.getStartTime();
    final endTime = await session.getEndTime();
    final duration = await session.getDuration();  
    // Console output generated for this execution
    final output = await session.getOutput();  
    // The stack trace if FFmpegKit fails to run a command
    final failStackTrace = await session.getFailStackTrace();  
    // The list of logs generated for this execution
    final logs = await session.getLogs();  
    // The list of statistics generated for this execution (only available on FFmpegSession)
    final statistics = await (session as FFmpegSession).getStatistics();  
});
```  
3. Execute `FFmpeg` commands by providing session specific `execute`/`log`/`session` callbacks.

```dart  
FFmpegKit.executeAsync('-i file1.mp4 -c:v mpeg4 file2.mp4', (Session session) async {
    // CALLED WHEN SESSION IS EXECUTED  
}, (Log log) {  
    // CALLED WHEN SESSION PRINTS LOGS  
}, (Statistics statistics) {  
    // CALLED WHEN SESSION GENERATES STATISTICS  
});
```  
4. Execute `FFprobe` commands.  
  
```dart  
FFprobeKit.execute(ffprobeCommand).then((session) async {  
    // CALLED WHEN SESSION IS EXECUTED  
});  
```  
5. Get media information for a file/url.

```dart  
FFprobeKit.getMediaInformation('<file path or url>').then((session) async {  
    final information = await session.getMediaInformation();  
    if (information == null) {  
        // CHECK THE FOLLOWING ATTRIBUTES ON ERROR
        final state = FFmpegKitConfig.sessionStateToString(await session.getState());
        final returnCode = await session.getReturnCode();
        final failStackTrace = await session.getFailStackTrace();
        final duration = await session.getDuration();
        final output = await session.getOutput();
    }
});
```  
6. Stop ongoing FFmpeg operations.  
  
- Stop all sessions  
```dart  
FFmpegKit.cancel();
```
- Stop a specific session  
```dart  
FFmpegKit.cancel(sessionId);  
```  
7. (Android) Convert Storage Access Framework (SAF) Uris into paths that can be read or written by  
   `FFmpegKit` and `FFprobeKit`.

- Reading a file:
```dart  
FFmpegKitConfig.selectDocumentForRead('*/*').then((uri) {  
    FFmpegKitConfig.getSafParameterForRead(uri!).then((safUrl) {
        FFmpegKit.executeAsync("-i ${safUrl!} -c:v mpeg4 file2.mp4");
    });
});
```  
- Writing to a file:  
```dart  
FFmpegKitConfig.selectDocumentForWrite('video.mp4', 'video/*').then((uri) {
    FFmpegKitConfig.getSafParameterForWrite(uri!).then((safUrl) {
        FFmpegKit.executeAsync("-i file1.mp4 -c:v mpeg4 ${safUrl}");
    });
});  
```  
8. Get previous `FFmpeg`, `FFprobe` and `MediaInformation` sessions from the session history.

```dart  
FFmpegKit.listSessions().then((sessionList) {  
    sessionList.forEach((session) {
        final sessionId = session.getSessionId();
    });
});  
FFprobeKit.listFFprobeSessions().then((sessionList) {
    sessionList.forEach((session) {
        final sessionId = session.getSessionId();
    });
});  
FFprobeKit.listMediaInformationSessions().then((sessionList) {
    sessionList.forEach((session) {
        final sessionId = session.getSessionId();
    });
});
```  
9. Enable global callbacks.  
  
- Session type specific Complete Callbacks, called when an async session has been completed  
  
```dart  
FFmpegKitConfig.enableFFmpegSessionCompleteCallback((session) {
    final sessionId = session.getSessionId();
});  
FFmpegKitConfig.enableFFprobeSessionCompleteCallback((session) {
    final sessionId = session.getSessionId();
});  
FFmpegKitConfig.enableMediaInformationSessionCompleteCallback((session) {
    final sessionId = session.getSessionId();
});  
```  
- Log Callback, called when a session generates logs

```dart  
FFmpegKitConfig.enableLogCallback((log) {  
    final message = log.getMessage();
});
```  
- Statistics Callback, called when a session generates statistics  
  
```dart  
FFmpegKitConfig.enableStatisticsCallback((statistics) {  
    final size = statistics.getSize();
});  
```  
10. Register system fonts and custom font directories.

```dart  
FFmpegKitConfig.setFontDirectoryList(["/system/fonts", "/System/Library/Fonts", "<folder with fonts>"]);
```
