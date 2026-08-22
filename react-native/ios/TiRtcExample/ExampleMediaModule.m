#import <React/RCTBridgeModule.h>

@interface RCT_EXTERN_MODULE(TiRtcExampleMedia, NSObject)

RCT_EXTERN_METHOD(requestGalleryWritePermission:(RCTPromiseResolveBlock)resolve
                  rejecter:(RCTPromiseRejectBlock)reject)
RCT_EXTERN_METHOD(cacheFilePath:(NSString *)extensionName
                  resolver:(RCTPromiseResolveBlock)resolve
                  rejecter:(RCTPromiseRejectBlock)reject)
RCT_EXTERN_METHOD(saveImageToGallery:(NSString *)sourcePath
                  resolver:(RCTPromiseResolveBlock)resolve
                  rejecter:(RCTPromiseRejectBlock)reject)
@end
