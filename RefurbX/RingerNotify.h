#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface RingerNotify : NSObject

/// Registers for com.apple.springboard.ringerstate. The handler receives YES when the ringer is silent.
+ (BOOL)watchOnQueue:(dispatch_queue_t)queue
             handler:(void (^)(BOOL silent))handler
               token:(int32_t *)token NS_SWIFT_NAME(watch(on:handler:token:));

+ (void)cancelToken:(int32_t)token NS_SWIFT_NAME(cancel(_:));

@end

NS_ASSUME_NONNULL_END
