//
// Copyright 2012 Square Inc.
// Portions Copyright (c) 2016-present, Facebook, Inc.
//
// All rights reserved.
//
// This source code is licensed under the BSD-style license found in the
// LICENSE file in the root directory of this source tree. An additional grant
// of patent rights can be found in the PATENTS file in the same directory.
//

#import "ARTSRRunLoopThread.h"

@interface ARTSRRunLoopThread ()

@property (atomic, strong, readwrite) NSRunLoop *runLoop;

@end

@implementation ARTSRRunLoopThread

+ (instancetype)sharedThread
{
    static ARTSRRunLoopThread *thread;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        thread = [[ARTSRRunLoopThread alloc] init];
        thread.name = @"io.ably.socketrocket.NetworkThread";
        [thread start];
    });
    return thread;
}

- (void)main
{
    @autoreleasepool {
        self.runLoop = [NSRunLoop currentRunLoop];

        // Add an empty run loop source to prevent runloop from spinning.
        CFRunLoopSourceContext sourceCtx = {
            .version = 0,
            .info = NULL,
            .retain = NULL,
            .release = NULL,
            .copyDescription = NULL,
            .equal = NULL,
            .hash = NULL,
            .schedule = NULL,
            .cancel = NULL,
            .perform = NULL
        };
        CFRunLoopSourceRef source = CFRunLoopSourceCreate(NULL, 0, &sourceCtx);
        CFRunLoopAddSource(CFRunLoopGetCurrent(), source, kCFRunLoopDefaultMode);
        CFRelease(source);

        while ([_runLoop runMode:NSDefaultRunLoopMode beforeDate:[NSDate distantFuture]]) {

        }
        assert(NO);
    }
}

@end
