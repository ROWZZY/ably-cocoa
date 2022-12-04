#import "ARTLocalDeviceStorage.h"
#import "ARTLog.h"
#import "ARTLocalDevice+Private.h"

@implementation ARTLocalDeviceStorage {
    ARTLog *_logger;
}

- (instancetype)initWithLogger:(ARTLog *)logger {
    if (self = [super init]) {
        _logger = logger;
    }
    return self;
}

+ (instancetype)newWithLogger:(ARTLog *)logger {
    return [[self alloc] initWithLogger:logger];
}

- (nullable id)objectForKey:(NSString *)key {
    return [NSUserDefaults.standardUserDefaults objectForKey:key];
}

- (void)setObject:(nullable id)value forKey:(NSString *)key {
    [NSUserDefaults.standardUserDefaults setObject:value forKey:key];
}

- (NSString *)secretForDevice:(ARTDeviceId *)deviceId {
    NSError *error = nil;
    NSString *value = [self keychainGetPasswordForService:ARTDeviceSecretKey account:(NSString *)deviceId error:&error];

    if ([error code] == errSecItemNotFound) {
        [_logger debug:__FILE__ line:__LINE__ message:@"Device Secret not found"];
    }
    else if (error) {
        [_logger error:@"Device Secret couldn't be read (%@)", [error localizedDescription]];
    }

    return value;
}

- (void)setSecret:(NSString *)value forDevice:(ARTDeviceId *)deviceId {
    NSError *error = nil;
    if (value == nil) {
        [self keychainDeletePasswordForService:ARTDeviceSecretKey account:(NSString *)deviceId error:&error];

        if ([error code] == errSecItemNotFound) {
            [_logger warn:@"Device Secret can't be deleted because it doesn't exist"];
        }
        else if (error) {
            [_logger error:@"Device Secret couldn't be updated (%@)", [error localizedDescription]];
        }
    }
    else {
        [self keychainSetPassword:value forService:ARTDeviceSecretKey account:(NSString *)deviceId error:&error];

        if (error) {
            [_logger error:@"Device Secret couldn't be updated (%@)", [error localizedDescription]];
        }
    }
}

#pragma mark - Keychain

- (nonnull NSMutableDictionary *)newKeychainQueryForService:(nonnull NSString *)serviceName account:(nonnull NSString *)account {
    NSMutableDictionary *dictionary = [NSMutableDictionary dictionaryWithCapacity:3];
    [dictionary setObject:(__bridge id)kSecClassGenericPassword forKey:(__bridge id)kSecClass];
    [dictionary setObject:serviceName forKey:(__bridge id)kSecAttrService];
    [dictionary setObject:account forKey:(__bridge id)kSecAttrAccount];
#if TARGET_OS_IPHONE
    [dictionary setObject:(__bridge id)kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly forKey:(__bridge id)kSecAttrAccessible];
#endif
    return dictionary;
}

- (nonnull NSError *)keychainErrorWithCode:(OSStatus)status {
    NSString *message = nil;
    #if TARGET_OS_IPHONE
    switch (status) {
        case errSecUnimplemented: {
            message = @"errSecUnimplemented";
            break;
        }
        case errSecParam: {
            message = @"errSecParam";
            break;
        }
        case errSecAllocate: {
            message = @"errSecAllocate";
            break;
        }
        case errSecNotAvailable: {
            message = @"errSecNotAvailable";
            break;
        }
        case errSecDuplicateItem: {
            message = @"errSecDuplicateItem";
            break;
        }
        case errSecItemNotFound: {
            message = @"errSecItemNotFound";
            break;
        }
        case errSecInteractionNotAllowed: {
            message = @"errSecInteractionNotAllowed";
            break;
        }
        case errSecDecode: {
            message = @"errSecDecode";
            break;
        }
        case errSecAuthFailed: {
            message = @"errSecAuthFailed";
            break;
        }
        default: {
            message = @"errSecDefault";
        }
    }
    #else
    message = (__bridge_transfer NSString *)SecCopyErrorMessageString(status, NULL);
    #endif
    NSDictionary *userInfo = nil;
    if (message) {
        userInfo = @{ NSLocalizedDescriptionKey : message };
    }
    return [NSError errorWithDomain:[NSString stringWithFormat:@"%@.%@", ARTAblyErrorDomain, @"Keychain"] code:status userInfo:userInfo];
}

- (nullable NSString *)keychainGetPasswordForService:(nonnull NSString *)serviceName account:(nonnull NSString *)account error:(NSError *__autoreleasing *)error {
    NSMutableDictionary *query = [self newKeychainQueryForService:serviceName account:account];

    [query setObject:@YES forKey:(__bridge id)kSecReturnData];
    [query setObject:(__bridge id)kSecMatchLimitOne forKey:(__bridge id)kSecMatchLimit];
    CFTypeRef result = NULL;
    OSStatus status = SecItemCopyMatching((__bridge CFDictionaryRef)query, &result);

    if (status != errSecSuccess) {
        if (error) {
            *error = [self keychainErrorWithCode:status];
        }
    }
    else {
        NSData *passwordData = (__bridge_transfer NSData *)result;
        if ([passwordData length]) {
            return [[NSString alloc] initWithData:passwordData encoding:NSUTF8StringEncoding];
        }
    }

    return nil;
}

- (BOOL)keychainDeletePasswordForService:(NSString *)serviceName account:(NSString *)account error:(NSError *__autoreleasing *)error {
    NSMutableDictionary *query = [self newKeychainQueryForService:serviceName account:account];
    OSStatus status = SecItemDelete((__bridge CFDictionaryRef)query);
    if (status != errSecSuccess && error != NULL) {
        *error = [self keychainErrorWithCode:status];
    }
    return (status == errSecSuccess);
}

- (BOOL)keychainSetPassword:(NSString *)password forService:(NSString *)serviceName account:(NSString *)account error:(NSError *__autoreleasing *)error {
    NSMutableDictionary *query = nil;
    NSMutableDictionary *searchQuery = [self newKeychainQueryForService:serviceName account:account];
    NSData *passwordData = [password dataUsingEncoding:NSUTF8StringEncoding];

    OSStatus status;
    status = SecItemCopyMatching((__bridge CFDictionaryRef)searchQuery, nil);
    if (status == errSecSuccess) { //item already exists, update it.
        query = [[NSMutableDictionary alloc] init];
        [query setObject:passwordData forKey:(__bridge id)kSecValueData];
        status = SecItemUpdate((__bridge CFDictionaryRef)(searchQuery), (__bridge CFDictionaryRef)(query));
    }
    else if (status == errSecItemNotFound) { //item not found, create it.
        query = [self newKeychainQueryForService:serviceName account:account];
        [query setObject:passwordData forKey:(__bridge id)kSecValueData];
        status = SecItemAdd((__bridge CFDictionaryRef)query, NULL);
    }

    if (status != errSecSuccess && error != NULL) {
        *error = [self keychainErrorWithCode:status];
    }

    return (status == errSecSuccess);
}

@end
