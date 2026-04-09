Pod::Spec.new do |s|
  s.name             = 'fast_thumbnail'
  s.version          = '0.1.0'
  s.summary          = 'Generate JPEG thumbnails using native macOS APIs.'
  s.description      = <<-DESC
A Flutter plugin that generates JPEG thumbnails using ImageIO on macOS.
                       DESC
  s.homepage         = 'https://github.com/hugocornellier/agelapse'
  s.license          = { :type => 'MIT' }
  s.author           = { 'Hugo Cornellier' => 'hugocornellier@gmail.com' }

  s.source           = { :path => '.' }
  s.source_files     = 'fast_thumbnail/Sources/fast_thumbnail/**/*.{swift,h,m}'

  s.dependency 'FlutterMacOS'

  s.platform = :osx, '10.14'
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES' }
  s.swift_version = '5.0'
end
