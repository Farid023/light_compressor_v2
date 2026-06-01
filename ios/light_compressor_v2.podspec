#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html.
# Run `pod lib lint light_compressor.podspec' to validate before publishing.
#
Pod::Spec.new do |s|
  s.name             = 'light_compressor_v2'
  s.version          = '1.0.1'
  s.summary          = 'Light Compressor Library'
  s.description      = <<-DESC
Light Video Compressor Library.
                       DESC
  s.homepage         = 'https://github.com/Farid023/light_compressor_v2'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'Farid Gurbanov' => 'gurfdev@gmail.com' }
  s.source           = { :path => '.' }
  s.source_files = 'light_compressor_v2/Sources/light_compressor_v2/**/*.swift'
  s.dependency 'Flutter'
  s.platform = :ios, '11.0'

  # Flutter.framework does not contain a i386 slice. Only x86_64 simulators are supported.
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES', 'VALID_ARCHS[sdk=iphonesimulator*]' => 'x86_64' }
  s.swift_version = '5.0'
end
