#import <Foundation/Foundation.h>
#import "ARTUtils.h"

NS_ASSUME_NONNULL_BEGIN

@interface ARTUtils (Private)

#pragma mark - Random generator

+ (void)seedRandomWithNumber:(unsigned int)number;
+ (void)seedRandomWithSystemTime;
+ (double)randomFraction;
+ (long)randomFromZeroToNumber:(long)number;

#pragma mark - Incremental backoff and jitter // RTB1

+ (double)jitterDelta;
+ (double)generateJitterCoefficient;
+ (double)backoffCoefficientForRetryNumber:(NSInteger)retryNumber;

@end

NS_ASSUME_NONNULL_END
