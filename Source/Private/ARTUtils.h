#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface ARTUtils : NSObject

#pragma mark - Incremental backoff and jitter (RTB1)

+ (NSTimeInterval)retryDelayFromInitialRetryTimeout:(NSTimeInterval)timeout forRetryNumber:(NSInteger)retryNumber;

@end

NS_ASSUME_NONNULL_END
