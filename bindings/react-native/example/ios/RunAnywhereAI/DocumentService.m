#import <React/RCTBridgeModule.h>

@interface RCT_EXTERN_MODULE(DocumentService, NSObject)

RCT_EXTERN_METHOD(extractText:(NSString *)filePath
                  withResolver:(RCTPromiseResolveBlock)resolve
                  withRejecter:(RCTPromiseRejectBlock)reject)

@end
