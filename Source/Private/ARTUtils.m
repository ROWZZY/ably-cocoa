#import <time.h>
#import <stdlib.h>
#import "ARTUtils.h"
#import "ARTUtils+Private.h"

@implementation ARTUtils

#pragma mark - Random generator

static BOOL _needsSeeding = YES;

+ (void)seedRandomWithNumber:(unsigned int)number {
    srandom(number);
    _needsSeeding = NO;
}

+ (void)seedRandomWithSystemTime {
    [self seedRandomWithNumber:(unsigned)time(NULL)];
}

+ (double)randomFraction {
    long r = [self randomFromZeroToNumber:100];
    return r / 100.0;
}

+ (long)randomFromZeroToNumber:(long)number {
    if (_needsSeeding) {
        [self seedRandomWithSystemTime];
    }
    return random() % number;
}

#pragma mark - Incremental backoff and jitter (RTB1)

+ (double)jitterDelta {
    return 0.2;
}

+ (double)generateJitterCoefficient {
    double coeff = 1.0 - self.randomFraction * self.jitterDelta;
    return coeff;
}

+ (double)backoffCoefficientForRetryNumber:(NSInteger)retryNumber {
    double coeff = MIN((NSTimeInterval)(retryNumber + 2.0) / 3.0, 2.0);
    return coeff;
}

+ (NSTimeInterval)retryDelayFromInitialRetryTimeout:(NSTimeInterval)timeout forRetryNumber:(NSInteger)retryNumber {
    timeout *= [self backoffCoefficientForRetryNumber:retryNumber] * [self generateJitterCoefficient];
    return timeout;
}

@end
