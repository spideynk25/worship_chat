#import "GallerySaverPlugin.h"

#if __has_include(<gallery_saver_plus/gallery_saver_plus-Swift.h>)
#import <gallery_saver_plus/gallery_saver_plus-Swift.h>
#else
#import "gallery_saver_plus-Swift.h"
#endif


@implementation GallerySaverPlugin
+ (void)registerWithRegistrar:(NSObject<FlutterPluginRegistrar>*)registrar {
  [SwiftGallerySaverPlugin registerWithRegistrar:registrar];
}
@end
