#import "RingerNotify.h"
#import <notify.h>

@implementation RingerNotify

+ (BOOL)watchOnQueue:(dispatch_queue_t)queue
             handler:(void (^)(BOOL silent))handler
               token:(int32_t *)token {
    if (queue == nil || handler == nil || token == nil) {
        return NO;
    }
    int registered = 0;
    uint32_t status = notify_register_dispatch(
        "com.apple.springboard.ringerstate",
        &registered,
        queue,
        ^(int notifyToken) {
            uint64_t state = 0;
            if (notify_get_state(notifyToken, &state) != NOTIFY_STATUS_OK) {
                return;
            }
            handler(state == 0);
        }
    );
    if (status != NOTIFY_STATUS_OK) {
        return NO;
    }
    *token = (int32_t)registered;
    uint64_t state = 0;
    if (notify_get_state(registered, &state) == NOTIFY_STATUS_OK) {
        handler(state == 0);
    }
    return YES;
}

+ (void)cancelToken:(int32_t)token {
    notify_cancel(token);
}

@end
