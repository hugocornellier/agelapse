Pod::Spec.new do |s|
  s.name             = 'ffmpeg_kit_flutter_new'
  s.version          = '1.0.0'
  s.summary          = 'FFmpeg Kit for Flutter'
  s.description      = 'A Flutter plugin for running FFmpeg and FFprobe commands.'
  s.homepage         = 'https://github.com/sk3llo/ffmpeg_kit_flutter'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'Anton Karpenko' => 'kapraton@gmail.com' }

  s.platform            = :ios
  s.requires_arc        = true
  s.static_framework    = true

  # Sources and prebuilt binaries are shared with the Swift Package Manager
  # package under ios/ffmpeg_kit_flutter_new/ (single source of truth).
  s.source              = { :path => '.' }
  s.source_files        = 'ffmpeg_kit_flutter_new/Sources/ffmpeg_kit_flutter_new/**/*.{h,m}'
  s.public_header_files = 'ffmpeg_kit_flutter_new/Sources/ffmpeg_kit_flutter_new/include/**/*.h'

  s.default_subspec = 'full-gpl'

  s.dependency          'Flutter'
  s.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'YES',
    'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'arm64 i386',
    'HEADER_SEARCH_PATHS' => '$(inherited) "$(PODS_TARGET_SRCROOT)/ffmpeg_kit_flutter_new/Frameworks/ffmpegkit.xcframework/ios-x86_64-simulator/ffmpegkit.framework/Headers" "$(PODS_TARGET_SRCROOT)/ffmpeg_kit_flutter_new/Frameworks/ffmpegkit.xcframework/ios-arm64/ffmpegkit.framework/Headers"'
  }

  s.subspec 'full-gpl' do |ss|
    # Adding pre-install hook
    s.prepare_command = <<-CMD
      if [ ! -d "./ffmpeg_kit_flutter_new/Frameworks" ]; then
        chmod +x ../scripts/setup_ios.sh
        ../scripts/setup_ios.sh
        fi
    CMD
    ss.source_files         = 'ffmpeg_kit_flutter_new/Sources/ffmpeg_kit_flutter_new/**/*.{h,m}'
    ss.public_header_files  = 'ffmpeg_kit_flutter_new/Sources/ffmpeg_kit_flutter_new/include/**/*.h'
    ss.ios.vendored_frameworks = 'ffmpeg_kit_flutter_new/Frameworks/ffmpegkit.xcframework',
                                 'ffmpeg_kit_flutter_new/Frameworks/libavcodec.xcframework',
                                 'ffmpeg_kit_flutter_new/Frameworks/libavdevice.xcframework',
                                 'ffmpeg_kit_flutter_new/Frameworks/libavfilter.xcframework',
                                 'ffmpeg_kit_flutter_new/Frameworks/libavformat.xcframework',
                                 'ffmpeg_kit_flutter_new/Frameworks/libavutil.xcframework',
                                 'ffmpeg_kit_flutter_new/Frameworks/libswresample.xcframework',
                                 'ffmpeg_kit_flutter_new/Frameworks/libswscale.xcframework'
    ss.ios.frameworks = 'AudioToolbox', 'CoreMedia'
    ss.libraries = 'z', 'bz2', 'c++', 'iconv'
    ss.ios.deployment_target = '14.0'
  end
end
