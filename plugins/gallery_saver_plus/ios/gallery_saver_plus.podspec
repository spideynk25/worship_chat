#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html
#
Pod::Spec.new do |s|
  s.name             = 'gallery_saver_plus'
  s.version          = '0.0.1'
  s.summary          = 'Saves images and videos to gallery and photos.'
  s.description      = <<-DESC
Saves images and videos to gallery and photos.
                       DESC
  s.homepage         = 'https://github.com/CarnegieTechnologies/gallery_saver'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'Carnegie Technologies d.o.o' => 'devoffice@carnegietechnologies.com' }
  s.source           = { :path => '.' }
  s.source_files = 'Classes/**/*'
  s.public_header_files = 'Classes/**/*.h'
  s.dependency 'Flutter'
  s.swift_version = '5.0'
  s.platform = :ios, '11.0'
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES' }
end
