#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html.
# Run `pod lib lint vn_editor.podspec` to validate before publishing.
#
Pod::Spec.new do |s|
  s.name             = 'vn_editor'
  s.version          = '0.1.0'
  s.summary          = 'A reusable Flutter video editing SDK with native Android and iOS media pipelines.'
  s.description      = <<-DESC
A reusable Flutter video editing SDK with native Android and iOS media pipelines.
                       DESC
  s.homepage         = 'https://github.com/sachinlal7/video_editor'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'Sachin Lal' => 'sachinlal7@users.noreply.github.com' }
  s.source           = { :path => '.' }
  s.source_files = 'vn_editor/Sources/vn_editor/**/*.{swift,h,m,mm}'
  s.resource_bundles = { 'vn_editor_resources' => ['vn_editor/Sources/vn_editor/Resources/*'] }
  s.dependency 'Flutter'
  s.platform = :ios, '15.0'

  # Flutter.framework does not contain a i386 slice.
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES', 'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386' }
  s.swift_version = '5.0'

  # If your plugin requires a privacy manifest, for example if it uses any
  # required reason APIs, update the PrivacyInfo.xcprivacy file to describe your
  # plugin's privacy impact, and then uncomment this line. For more information,
  # see https://developer.apple.com/documentation/bundleresources/privacy_manifest_files
  # s.resource_bundles = {'vn_editor_privacy' => ['vn_editor/Sources/vn_editor/PrivacyInfo.xcprivacy']}
end
