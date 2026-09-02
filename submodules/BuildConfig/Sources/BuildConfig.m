#import <BuildConfig/BuildConfig.h>

static NSString *telegramApplicationSecretKey = @"telegramApplicationSecretKey_v3";
API_AVAILABLE(ios(10))
@interface LocalPrivateKey : NSObject {
    SecKeyRef _privateKey;
    SecKeyRef _publicKey;
}

- (NSData * _Nullable)encrypt:(NSData * _Nonnull)data;
- (NSData * _Nullable)decrypt:(NSData * _Nonnull)data cancelled:(bool *)cancelled;

@end

@implementation LocalPrivateKey

- (instancetype _Nonnull)initWithPrivateKey:(SecKeyRef)privateKey publicKey:(SecKeyRef)publicKey {
    self = [super init];
    if (self != nil) {
        _privateKey = (SecKeyRef)CFRetain(privateKey);
        _publicKey = (SecKeyRef)CFRetain(publicKey);
    }
    return self;
}

- (void)dealloc {
    CFRelease(_privateKey);
    CFRelease(_publicKey);
}

- (NSData * _Nullable)getPublicKey {
    NSData *result = CFBridgingRelease(SecKeyCopyExternalRepresentation(_publicKey, nil));
    return result;
}

- (NSData * _Nullable)encrypt:(NSData * _Nonnull)data {
    if (data.length % 16 != 0) {
        return nil;
    }
    
    CFErrorRef error = NULL;
    NSData *cipherText = (NSData *)CFBridgingRelease(SecKeyCreateEncryptedData(_publicKey, kSecKeyAlgorithmECIESEncryptionCofactorX963SHA256AESGCM, (__bridge CFDataRef)data, &error));
    
    if (!cipherText) {
        __unused NSError *err = CFBridgingRelease(error);
        return nil;
    }
    
    return cipherText;
}

- (NSData * _Nullable)decrypt:(NSData * _Nonnull)data cancelled:(bool *)cancelled {    
    CFErrorRef error = NULL;
    NSData *plainText = (NSData *)CFBridgingRelease(SecKeyCreateDecryptedData(_privateKey, kSecKeyAlgorithmECIESEncryptionCofactorX963SHA256AESGCM, (__bridge CFDataRef)data, &error));
    
    if (!plainText) {
        __unused NSError *err = CFBridgingRelease(error);
        if (err.code == -2) {
            if (cancelled) {
                *cancelled = true;
            }
        }
        return nil;
    }
    
    return plainText;
}

@end

@interface BuildConfig () {
    NSData * _Nullable _bundleData;
    int32_t _apiId;
    NSString * _Nonnull _apiHash;
    NSString * _Nullable _appCenterId;
    NSMutableDictionary * _Nonnull _dataDict;
}

@end

@implementation DeviceSpecificEncryptionParameters

- (instancetype)initWithKey:(NSData * _Nonnull)key salt:(NSData * _Nonnull)salt {
    self = [super init];
    if (self != nil) {
        _key = key;
        _salt = salt;
    }
    return self;
}

@end

// MARK: Jerkgram Build124 API identity proof
#define JERKGRAM_BUILD124_STRINGIFY_INNER(value) #value
#define JERKGRAM_BUILD124_STRINGIFY(value) JERKGRAM_BUILD124_STRINGIFY_INNER(value)
__attribute__((used))
static const char jerkgramBuild124ApiIdOwner[] =
    "JERKGRAM_BUILD124_API_ID=" JERKGRAM_BUILD124_STRINGIFY(APP_CONFIG_API_ID);

@implementation BuildConfig

+ (NSString *)bundleId {
    NSDictionary *query = [NSDictionary dictionaryWithObjectsAndKeys:
        (__bridge NSString *)kSecClassGenericPassword, (__bridge NSString *)kSecClass,
        @"bundleSeedID", kSecAttrAccount,
        @"", kSecAttrService,
        (id)kCFBooleanTrue, kSecReturnAttributes,
    nil];
    CFDictionaryRef result = nil;
    OSStatus status = SecItemCopyMatching((__bridge CFDictionaryRef)query, (CFTypeRef *)&result);
    if (status == errSecItemNotFound) {
        status = SecItemAdd((__bridge CFDictionaryRef)query, (CFTypeRef *)&result);
    }
    if (status != errSecSuccess) {
        return nil;
    }
    NSString *accessGroup = [(__bridge NSDictionary *)result objectForKey:(__bridge NSString *)kSecAttrAccessGroup];
    NSArray *components = [accessGroup componentsSeparatedByString:@"."];
    NSString *bundleSeedID = [[components objectEnumerator] nextObject];
    CFRelease(result);
    return bundleSeedID;
}

+ (instancetype _Nonnull)sharedBuildConfig {
    static BuildConfig *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[BuildConfig alloc] init];
    });
    return instance;
}

- (instancetype _Nonnull)initWithBaseAppBundleId:(NSString * _Nonnull)baseAppBundleId {
    self = [super init];
    if (self != nil) {
        _apiId = APP_CONFIG_API_ID;
        _apiHash = @(APP_CONFIG_API_HASH);
        _appCenterId = @(APP_CONFIG_APP_CENTER_ID);
        
        _dataDict = [[NSMutableDictionary alloc] init];
        
        if (baseAppBundleId != nil) {
            _dataDict[@"bundleId"] = baseAppBundleId;
        }
    }
    return self;
}

- (NSData * _Nullable)bundleDataWithAppToken:(NSData * _Nullable)appToken tokenType:(NSString * _Nullable)tokenType tokenEnvironment:(NSString * _Nullable)tokenEnvironment signatureDict:(NSDictionary * _Nullable)signatureDict {
    NSMutableDictionary *dataDict = [[NSMutableDictionary alloc] initWithDictionary:_dataDict];
    if (appToken != nil) {
        dataDict[@"device_token"] = [appToken base64EncodedStringWithOptions:0];
        if (tokenType != nil) {
            dataDict[@"device_token_type"] = tokenType;
        }
        if (tokenEnvironment != nil) {
            dataDict[@"device_token_environment"] = tokenEnvironment;
        }
    }
    float tzOffset = [[NSTimeZone systemTimeZone] secondsFromGMT];
    dataDict[@"tz_offset"] = @((int)tzOffset);
    if (signatureDict != nil) {
        for (id<NSCopying> key in signatureDict.allKeys) {
            dataDict[key] = signatureDict[key];
        }
    }
    NSData *data = [NSJSONSerialization dataWithJSONObject:dataDict options:0 error:nil];
    return data;
}

- (int32_t)apiId {
    return _apiId;
}

- (NSString * _Nonnull)apiHash {
    return _apiHash;
}

- (NSString * _Nullable)appCenterId {
    return _appCenterId;
}

- (bool)isInternalBuild {
    return APP_CONFIG_IS_INTERNAL_BUILD;
}

- (bool)isAppStoreBuild {
    return APP_CONFIG_IS_APPSTORE_BUILD;
}

- (int64_t)appStoreId {
    return APP_CONFIG_APPSTORE_ID;
}

- (NSString *)appSpecificUrlScheme {
    return @(APP_SPECIFIC_URL_SCHEME);
}

- (bool)isICloudEnabled {
    return APP_CONFIG_IS_ICLOUD_ENABLED;
}

- (bool)isSiriEnabled {
    return APP_CONFIG_IS_SIRI_ENABLED;
}

+ (NSString * _Nullable)bundleSeedId {
    NSDictionary *query = [NSDictionary dictionaryWithObjectsAndKeys:
       (__bridge NSString *)kSecClassGenericPassword, (__bridge NSString *)kSecClass,
       @"bundleSeedID", kSecAttrAccount,
       @"", kSecAttrService,
       (id)kCFBooleanTrue, kSecReturnAttributes,
    nil];
    CFDictionaryRef result = nil;
    OSStatus status = SecItemCopyMatching((__bridge CFDictionaryRef)query, (CFTypeRef *)&result);
    if (status == errSecItemNotFound) {
        status = SecItemAdd((__bridge CFDictionaryRef)query, (CFTypeRef *)&result);
    }
    if (status != errSecSuccess) {
        return nil;
    }
    NSString *accessGroup = [(__bridge NSDictionary *)result objectForKey:(__bridge NSString *)kSecAttrAccessGroup];
    NSArray *components = [accessGroup componentsSeparatedByString:@"."];
    NSString *bundleSeedID = [[components objectEnumerator] nextObject];
    CFRelease(result);
    return bundleSeedID;
}

+ (NSData * _Nullable)applicationSecretTag:(bool)isCheckKey {
    if (isCheckKey) {
        return [[telegramApplicationSecretKey stringByAppendingString:@"_check"] dataUsingEncoding:NSUTF8StringEncoding];
    } else {
        return [telegramApplicationSecretKey dataUsingEncoding:NSUTF8StringEncoding];
    }
}

+ (LocalPrivateKey * _Nullable)getApplicationSecretKey:(NSString * _Nonnull)baseAppBundleId isCheckKey:(bool)isCheckKey API_AVAILABLE(ios(10)) {
    NSString *bundleSeedId = [self bundleSeedId];
    if (bundleSeedId == nil) {
        return nil;
    }
    
    NSData *applicationTag = [self applicationSecretTag:isCheckKey];
    NSString *accessGroup = [bundleSeedId stringByAppendingFormat:@".%@", baseAppBundleId];
    
    NSDictionary *query = @{
        (id)kSecClass: (id)kSecClassKey,
        (id)kSecAttrApplicationTag: applicationTag,
        (id)kSecAttrKeyType: (id)kSecAttrKeyTypeECSECPrimeRandom,
        (id)kSecAttrAccessGroup: (id)accessGroup,
        (id)kSecReturnRef: @YES
    };
    SecKeyRef privateKey = NULL;
    OSStatus status = SecItemCopyMatching((__bridge CFDictionaryRef)query, (CFTypeRef *)&privateKey);
    if (status != errSecSuccess) {
        return nil;
    }
    
    SecKeyRef publicKey = SecKeyCopyPublicKey(privateKey);
    if (!publicKey) {
        if (privateKey) {
            CFRelease(privateKey);
        }
        return nil;
    }
    
    LocalPrivateKey *result = [[LocalPrivateKey alloc] initWithPrivateKey:privateKey publicKey:publicKey];
    
    if (publicKey) {
        CFRelease(publicKey);
    }
    if (privateKey) {
        CFRelease(privateKey);
    }
    
    return result;
}

+ (bool)removeApplicationSecretKey:(NSString * _Nonnull)baseAppBundleId isCheckKey:(bool)isCheckKey API_AVAILABLE(ios(10)) {
    NSString *bundleSeedId = [self bundleSeedId];
    if (bundleSeedId == nil) {
        return nil;
    }
    
    NSData *applicationTag = [self applicationSecretTag:isCheckKey];
    NSString *accessGroup = [bundleSeedId stringByAppendingFormat:@".%@", baseAppBundleId];
    
    NSDictionary *query = @{
        (id)kSecClass: (id)kSecClassKey,
        (id)kSecAttrApplicationTag: applicationTag,
        (id)kSecAttrKeyType: (id)kSecAttrKeyTypeECSECPrimeRandom,
        (id)kSecAttrAccessGroup: (id)accessGroup
    };
    OSStatus status = SecItemDelete((__bridge CFDictionaryRef)query);
    if (status != errSecSuccess) {
        return false;
    }
    return true;
}

+ (LocalPrivateKey * _Nullable)addApplicationSecretKey:(NSString * _Nonnull)baseAppBundleId isCheckKey:(bool)isCheckKey API_AVAILABLE(ios(10)) {
    NSString *bundleSeedId = [self bundleSeedId];
    if (bundleSeedId == nil) {
        return nil;
    }
    
    NSData *applicationTag = [self applicationSecretTag:isCheckKey];
    NSString *accessGroup = [bundleSeedId stringByAppendingFormat:@".%@", baseAppBundleId];
    
    SecAccessControlRef access;
    if (isCheckKey) {
        access = SecAccessControlCreateWithFlags(kCFAllocatorDefault, kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly, kSecAccessControlPrivateKeyUsage, NULL);
    } else {
        access = SecAccessControlCreateWithFlags(kCFAllocatorDefault, kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly, kSecAccessControlUserPresence | kSecAccessControlPrivateKeyUsage, NULL);
    }
    NSDictionary *attributes = @{
        (id)kSecAttrKeyType: (id)kSecAttrKeyTypeECSECPrimeRandom,
        (id)kSecAttrKeySizeInBits: @256,
        (id)kSecAttrTokenID: (id)kSecAttrTokenIDSecureEnclave,
        (id)kSecPrivateKeyAttrs: @{
            (id)kSecAttrIsPermanent: @YES,
            (id)kSecAttrApplicationTag: applicationTag,
            (id)kSecAttrAccessControl: (__bridge id)access,
            (id)kSecAttrAccessGroup: (id)accessGroup,
        },
    };
    
    CFErrorRef error = NULL;
    SecKeyRef privateKey = SecKeyCreateRandomKey((__bridge CFDictionaryRef)attributes, &error);
    if (!privateKey) {
        if (access) {
            CFRelease(access);
        }
        
        __unused NSError *err = CFBridgingRelease(error);
        return nil;
    }
    
    SecKeyRef publicKey = SecKeyCopyPublicKey(privateKey);
    if (!publicKey) {
        if (privateKey) {
            CFRelease(privateKey);
        }
        if (access) {
            CFRelease(access);
        }
        
        __unused NSError *err = CFBridgingRelease(error);
        return nil;
    }
    
    LocalPrivateKey *result = [[LocalPrivateKey alloc] initWithPrivateKey:privateKey publicKey:publicKey];
    
    if (publicKey) {
        CFRelease(publicKey);
    }
    if (privateKey) {
        CFRelease(privateKey);
    }
    if (access) {
        CFRelease(access);
    }
    
    return result;
}

+ (DeviceSpecificEncryptionParameters * _Nonnull)deviceSpecificEncryptionParameters:(NSString * _Nonnull)rootPath baseAppBundleId:(NSString * _Nonnull)baseAppBundleId {
    CFAbsoluteTime startTime = CFAbsoluteTimeGetCurrent();
    
    NSString *filePath = [rootPath stringByAppendingPathComponent:@".tempkey"];
    //NSString *encryptedPath = [rootPath stringByAppendingPathComponent:@".tempkeyEncrypted"];
    
    NSData *currentData = [NSData dataWithContentsOfFile:filePath];
    NSData *resultData = nil;
    if (currentData != nil && currentData.length == 32 + 16) {
        resultData = currentData;
    }
    if (resultData == nil) {
        NSMutableData *randomData = [[NSMutableData alloc] initWithLength:32 + 16];
        int result = SecRandomCopyBytes(kSecRandomDefault, randomData.length, [randomData mutableBytes]);
        if (currentData != nil && currentData.length == 32) { // upgrade key with salt
            [currentData getBytes:randomData.mutableBytes length:32];
        }
        assert(result == 0);
        resultData = randomData;
        [resultData writeToFile:filePath atomically:false];
    }
    
    /*if (@available(iOS 11, *)) {
        NSData *currentEncryptedData = [NSData dataWithContentsOfFile:encryptedPath];
        
        LocalPrivateKey *localPrivateKey = [self getLocalPrivateKey:baseAppBundleId];
        
        if (localPrivateKey == nil) {
            localPrivateKey = [self addLocalPrivateKey:baseAppBundleId];
        }
    
        if (localPrivateKey != nil) {
            if (currentEncryptedData != nil) {
                NSData *decryptedData = [localPrivateKey decrypt:currentEncryptedData];
                
                if (![resultData isEqualToData:decryptedData]) {
                    NSData *encryptedData = [localPrivateKey encrypt:resultData];
                    [encryptedData writeToFile:encryptedPath atomically:false];
                    //assert(false);
                }
            } else {
                NSData *encryptedData = [localPrivateKey encrypt:resultData];
                [encryptedData writeToFile:encryptedPath atomically:false];
            }
        }
    }*/
    
    CFAbsoluteTime endTime = CFAbsoluteTimeGetCurrent();
    NSLog(@"deviceSpecificEncryptionParameters took %f ms", (endTime - startTime) * 1000.0);
    
    NSData *key = [resultData subdataWithRange:NSMakeRange(0, 32)];
    NSData *salt = [resultData subdataWithRange:NSMakeRange(32, 16)];
    return [[DeviceSpecificEncryptionParameters alloc] initWithKey:key salt:salt];
}

+ (dispatch_queue_t)encryptionQueue {
    static dispatch_queue_t instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = dispatch_queue_create("encryptionQueue", 0);
    });
    return instance;
}

+ (void)getHardwareEncryptionAvailableWithBaseAppBundleId:(NSString * _Nonnull)baseAppBundleId completion:(void (^)(NSData * _Nullable))completion {
    dispatch_async([self encryptionQueue], ^{
        LocalPrivateKey *checkKey = [self getApplicationSecretKey:baseAppBundleId isCheckKey:true];
        if (checkKey != nil) {
            NSData *sampleData = [checkKey encrypt:[NSData data]];
            if (sampleData == nil) {
                [self removeApplicationSecretKey:baseAppBundleId isCheckKey:false];
                [self removeApplicationSecretKey:baseAppBundleId isCheckKey:true];
            } else {
                NSData *decryptedData = [checkKey decrypt:sampleData cancelled: nil];
                if (decryptedData == nil) {
                    [self removeApplicationSecretKey:baseAppBundleId isCheckKey:false];
                    [self removeApplicationSecretKey:baseAppBundleId isCheckKey:true];
                }
            }
        } else {
            [self removeApplicationSecretKey:baseAppBundleId isCheckKey:false];
            [self removeApplicationSecretKey:baseAppBundleId isCheckKey:true];
        }
        
        LocalPrivateKey *privateKey = [self getApplicationSecretKey:baseAppBundleId isCheckKey:false];
        if (privateKey == nil) {
            [self removeApplicationSecretKey:baseAppBundleId isCheckKey:false];
            [self removeApplicationSecretKey:baseAppBundleId isCheckKey:true];
            privateKey = [self addApplicationSecretKey:baseAppBundleId isCheckKey:false];
            privateKey = [self addApplicationSecretKey:baseAppBundleId isCheckKey:true];
        }
        completion([privateKey getPublicKey]);
    });
}

+ (void)encryptApplicationSecret:(NSData * _Nonnull)secret baseAppBundleId:(NSString * _Nonnull)baseAppBundleId completion:(void (^)(NSData * _Nullable, NSData * _Nullable))completion {
    dispatch_async([self encryptionQueue], ^{
        LocalPrivateKey *privateKey = [self getApplicationSecretKey:baseAppBundleId isCheckKey:false];
        if (privateKey == nil) {
            [self removeApplicationSecretKey:baseAppBundleId isCheckKey:false];
            [self removeApplicationSecretKey:baseAppBundleId isCheckKey:true];
            privateKey = [self addApplicationSecretKey:baseAppBundleId isCheckKey:false];
            privateKey = [self addApplicationSecretKey:baseAppBundleId isCheckKey:true];
        }
        if (privateKey == nil) {
            completion(nil, nil);
            return;
        }
        NSData *result = [privateKey encrypt:secret];
        completion(result, [privateKey getPublicKey]);
    });
}

+ (void)decryptApplicationSecret:(NSData * _Nonnull)secret publicKey:(NSData * _Nonnull)publicKey baseAppBundleId:(NSString * _Nonnull)baseAppBundleId completion:(void (^)(NSData * _Nullable, bool))completion {
    dispatch_async([self encryptionQueue], ^{
        LocalPrivateKey *privateKey = [self getApplicationSecretKey:baseAppBundleId isCheckKey:false];
        if (privateKey == nil) {
            completion(nil, false);
            return;
        }
        if (privateKey == nil) {
            completion(nil, false);
            return;
        }
        NSData *currentPublicKey = [privateKey getPublicKey];
        if (currentPublicKey == nil) {
            completion(nil, false);
            return;
        }
        if (![publicKey isEqualToData:currentPublicKey]) {
            completion(nil, false);
            return;
        }
        bool cancelled = false;
        NSData *result = [privateKey decrypt:secret cancelled:&cancelled];
        completion(result, cancelled);
    });
}

@end


// MARK: Jerkgram v1.2E BUILD116_EXTENSION_DIAGNOSTICS1
static NSString *JerkgramDiagnosticsDirectory(NSString *sharedContainerPath) {
    return [sharedContainerPath stringByAppendingPathComponent:@"telegram-data/jerkgram-extension-diagnostics"];
}

static NSString *JerkgramResolvedDiagnosticsGroup(void) {
    NSMutableArray<NSURL *> *profileURLs = [[NSMutableArray alloc] init];
    NSURL *bundleURL = NSBundle.mainBundle.bundleURL;
    [profileURLs addObject:[bundleURL URLByAppendingPathComponent:@"embedded.mobileprovision"]];
    NSURL *containingApp = bundleURL.URLByDeletingLastPathComponent.URLByDeletingLastPathComponent;
    if ([containingApp.pathExtension isEqualToString:@"app"]) {
        [profileURLs addObject:[containingApp URLByAppendingPathComponent:@"embedded.mobileprovision"]];
    }
    for (NSURL *profileURL in profileURLs) {
        NSData *data = [NSData dataWithContentsOfURL:profileURL];
        if (data == nil) {
            continue;
        }
        NSString *text = [[NSString alloc] initWithData:data encoding:NSISOLatin1StringEncoding];
        NSRange start = [text rangeOfString:@"<plist"];
        NSRange end = [text rangeOfString:@"</plist>" options:NSBackwardsSearch];
        if (start.location == NSNotFound || end.location == NSNotFound) {
            continue;
        }
        NSRange range = NSMakeRange(start.location, NSMaxRange(end) - start.location);
        NSData *plistData = [[text substringWithRange:range] dataUsingEncoding:NSUTF8StringEncoding];
        NSDictionary *root = [NSPropertyListSerialization propertyListWithData:plistData options:0 format:nil error:nil];
        NSArray<NSString *> *groups = root[@"Entitlements"][@"com.apple.security.application-groups"];
        NSString *fallback = [@"group." stringByAppendingString:NSBundle.mainBundle.bundleIdentifier ?: @""];
        if ([groups containsObject:fallback]) {
            return fallback;
        }
        NSArray<NSString *> *roleOne = [groups filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(NSString *value, NSDictionary *_) {
            return [value hasSuffix:@".1"];
        }]];
        if (roleOne.count == 1) {
            return roleOne.firstObject;
        }
        if (groups.count == 1) {
            return groups.firstObject;
        }
    }
    return [@"group." stringByAppendingString:NSBundle.mainBundle.bundleIdentifier ?: @""];
}

@implementation BuildConfig (JerkgramExtensionDiagnostics)

+ (void)jerkgramRecordExtensionDiagnosticWithProcess:(NSString *)process
    stage:(NSString *)stage
    appGroupIdentifier:(NSString *)appGroupIdentifier
    sharedContainerPath:(NSString *)sharedContainerPath
    detail:(NSString *)detail {
    NSString *boundedDetail = detail ?: @"";
    if (boundedDetail.length > 240) {
        boundedDetail = [boundedDetail substringToIndex:240];
    }
    NSLog(@"[JerkgramExtension] %@ %@ group=%@ path=%@ %@", process, stage, appGroupIdentifier, sharedContainerPath, boundedDetail);
    if (sharedContainerPath.length == 0) {
        return;
    }
    NSString *directory = JerkgramDiagnosticsDirectory(sharedContainerPath);
    [NSFileManager.defaultManager createDirectoryAtPath:directory withIntermediateDirectories:YES attributes:nil error:nil];
    NSDictionary *record = @{
        @"schemaVersion": @1,
        @"process": process ?: @"unknown",
        @"stage": stage ?: @"unknown",
        @"appGroupIdentifier": appGroupIdentifier ?: @"",
        @"sharedContainerPath": sharedContainerPath ?: @"",
        @"detail": boundedDetail,
        @"timestampMs": @((long long)(NSDate.date.timeIntervalSince1970 * 1000.0))
    };
    NSData *json = [NSJSONSerialization dataWithJSONObject:record options:NSJSONWritingSortedKeys error:nil];
    NSString *safeProcess = [[process ?: @"unknown" componentsSeparatedByCharactersInSet:NSCharacterSet.alphanumericCharacterSet.invertedSet] componentsJoinedByString:@"_"];
    NSURL *fileURL = [NSURL fileURLWithPath:[directory stringByAppendingPathComponent:[safeProcess stringByAppendingPathExtension:@"json"]]];
    [json writeToURL:fileURL options:NSDataWritingAtomic error:nil];
}

+ (NSString *)jerkgramExtensionDiagnosticsReport {
    NSString *group = JerkgramResolvedDiagnosticsGroup();
    NSURL *container = [NSFileManager.defaultManager containerURLForSecurityApplicationGroupIdentifier:group];
    if (container == nil) {
        return @"{\"schemaVersion\":1,\"error\":\"shared-container-unavailable\"}";
    }
    NSString *directory = JerkgramDiagnosticsDirectory(container.path);
    NSArray<NSString *> *names = [[NSFileManager.defaultManager contentsOfDirectoryAtPath:directory error:nil] sortedArrayUsingSelector:@selector(compare:)];
    NSMutableArray *records = [[NSMutableArray alloc] init];
    for (NSString *name in [names subarrayWithRange:NSMakeRange(0, MIN(names.count, 16))]) {
        NSData *data = [NSData dataWithContentsOfFile:[directory stringByAppendingPathComponent:name]];
        id record = data == nil ? nil : [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
        if (record != nil) {
            [records addObject:record];
        }
    }
    NSDictionary *report = @{@"schemaVersion": @1, @"appGroupIdentifier": group, @"records": records};
    NSData *json = [NSJSONSerialization dataWithJSONObject:report options:(NSJSONWritingPrettyPrinted | NSJSONWritingSortedKeys) error:nil];
    return [[NSString alloc] initWithData:json encoding:NSUTF8StringEncoding] ?: @"{}";
}


// MARK: Jerkgram v1.2F BUILD117_EXTENSION_BOUNDARY_CLASSIFIER1
+ (NSString *)jerkgramExtensionContainerClassificationForPath:(NSString *)path {
    if (path.length == 0) {
        return @"missing";
    }
    if ([path containsString:@"/Containers/Shared/AppGroup/"]) {
        return @"shared";
    }
    if ([path hasSuffix:@"/Documents/AppGroup"] || [path containsString:@"/Documents/AppGroup/"]) {
        return @"processLocal";
    }
    return @"other";
}

+ (NSString *)jerkgramExtensionBoundarySummaryWithProcess:(NSString *)process
    stage:(NSString *)stage
    path:(NSString *)path {
    NSString *classification = [self jerkgramExtensionContainerClassificationForPath:path];
    NSString *safeProcess = process.length == 0 ? @"extension" : process;
    NSString *safeStage = stage.length == 0 ? @"unknown" : stage;
    return [NSString stringWithFormat:
        @"Jerkgram %@: %@ failed (container=%@). Open the main app once, then retry. If this remains processLocal, the signer isolated the App Group.",
        safeProcess, safeStage, classification];
}

@end
