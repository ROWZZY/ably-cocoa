#import <Ably/ARTDefault.h>

extern NSString *const ARTDefaultProduction;

@interface ARTDefault (Private)

+ (void)setRealtimeRequestTimeout:(NSTimeInterval)value;
+ (void)setConnectionStateTtl:(NSTimeInterval)value;
+ (void)setMaxMessageSize:(NSInteger)value;

@end
