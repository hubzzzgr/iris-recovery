#import "IrisPreferences.h"
#import <CoreFoundation/CoreFoundation.h>
#include <string.h>
#include <zstd.h>

NSNotificationName const IrisPreferencesDidChange = @"IrisPreferencesDidChange";
NSString *const IrisHeaderEnabled = @"iris_header_enabled";
NSString *const IrisHeaderSubtitleEnabled = @"iris_header_subtitle_enabled";
NSString *const IrisHeaderTitle = @"iris_custom_header_title";
NSString *const IrisHeaderSubtitle = @"iris_custom_header_subtitle";
NSString *const IrisHeaderColorHex = @"iris_header_color_hex";
NSString *const IrisSubtitleColorHex = @"iris_subtitle_color_hex";
NSString *const IrisSwitchColorHex = @"iris_switch_color_hex";
NSString *const IrisRainbowRefresh = @"iris_rainbow_ptr";
NSString *const IrisRainbowStyle = @"iris_rainbow_ptr_style";
NSString *const IrisRefreshIndicatorColorHex = @"iris_reload_indicator_color_hex";
NSString *const IrisRainbowFirstColorHex = @"iris_rainbow_custom1_hex";
NSString *const IrisRainbowSecondColorHex = @"iris_rainbow_custom2_hex";
NSString *const IrisRainbowThirdColorHex = @"iris_rainbow_custom3_hex";

static const char IrisTransferMagic[] = "IRS1";
static const NSUInteger IrisTransferLimit = 2 * 1024 * 1024;
static const NSUInteger IrisQRTextLimit = 2200;
static BOOL IrisApplyAppearance(NSDictionary *values, BOOL replace, NSError **error);

NSArray<NSString *> *IrisRainbowStyles(void) {
    return @[@"classic", @"sunset", @"ocean", @"aurora", @"candy", @"custom"];
}

static NSDictionary<NSString *, id> *IrisAppearanceDefaults(void) {
    static NSDictionary *defaults;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        defaults = @{
            IrisHeaderEnabled: @YES, IrisHeaderSubtitleEnabled: @NO,
            IrisHeaderTitle: @"Iris", IrisHeaderSubtitle: @"", IrisHeaderColorHex: @"",
            IrisSubtitleColorHex: @"", IrisSwitchColorHex: @"",
            IrisRainbowRefresh: @NO, IrisRainbowStyle: @"classic", IrisRefreshIndicatorColorHex: @"",
            IrisRainbowFirstColorHex: @"", IrisRainbowSecondColorHex: @"", IrisRainbowThirdColorHex: @"",
        };
    });
    return defaults;
}

static BOOL IrisFail(NSError **error, NSString *message) {
    if (error) {
        *error = [NSError errorWithDomain:@"IrisAppearance" code:1
                                 userInfo:@{NSLocalizedDescriptionKey: message}];
    }
    return NO;
}

static id IrisNormalizedValue(NSString *key, id value) {
    id fallback = IrisAppearanceDefaults()[key];
    if ([fallback isKindOfClass:NSNumber.class]) {
        return [value isKindOfClass:NSNumber.class]
            && CFGetTypeID((__bridge CFTypeRef)value) == CFBooleanGetTypeID() ? value : nil;
    }
    if (!fallback || ![value isKindOfClass:NSString.class]) return nil;
    NSString *string = value;
    if ([key isEqualToString:IrisRainbowStyle]) {
        return [IrisRainbowStyles() containsObject:string] ? string : nil;
    }
    if ([key hasSuffix:@"_hex"]) {
        NSString *hex = [string hasPrefix:@"#"] ? [string substringFromIndex:1] : string;
        NSCharacterSet *invalid = [[NSCharacterSet characterSetWithCharactersInString:@"0123456789ABCDEFabcdef"] invertedSet];
        if (!hex.length) return @"";
        if (hex.length != 6 || [hex rangeOfCharacterFromSet:invalid].location != NSNotFound) return nil;
        return [@"#" stringByAppendingString:hex.uppercaseString];
    }
    if (string.length > 80 || [string rangeOfCharacterFromSet:NSCharacterSet.newlineCharacterSet].location != NSNotFound) return nil;
    return string;
}

NSDictionary<NSString *, id> *IrisAppearancePreferences(void) {
    NSDictionary *fallbacks = IrisAppearanceDefaults();
    NSMutableDictionary *values = [fallbacks mutableCopy];
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    for (NSString *key in fallbacks) {
        id value = IrisNormalizedValue(key, [defaults objectForKey:key]);
        if (value) values[key] = value;
    }
    // Older rebuilds used the title color for the subtitle as well.
    if (![defaults objectForKey:IrisSubtitleColorHex]) values[IrisSubtitleColorHex] = values[IrisHeaderColorHex];
    return [values copy];
}

static void IrisSaveAppearance(NSDictionary<NSString *, id> *values) {
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    [values enumerateKeysAndObjectsUsingBlock:^(NSString *key, id value, BOOL *stop) {
        (void)stop;
        [defaults setObject:value forKey:key];
    }];
    [NSNotificationCenter.defaultCenter postNotificationName:IrisPreferencesDidChange object:nil];
}

BOOL IrisSetAppearanceValue(NSString *key, id value, NSError **error) {
    id normalized = IrisNormalizedValue(key, value);
    if (!normalized) {
        NSString *message = [key hasSuffix:@"_hex"]
            ? @"Enter a six-digit hex color, or leave the field empty."
            : @"Enter a single line of up to 80 characters.";
        return IrisFail(error, message);
    }
    IrisSaveAppearance(@{key: normalized});
    return YES;
}

NSData *IrisExportAppearance(NSError **error) {
    return [NSJSONSerialization dataWithJSONObject:@{@"format": @"iris-appearance", @"version": @1,
                                                      @"values": IrisAppearancePreferences()}
                                           options:NSJSONWritingPrettyPrinted | NSJSONWritingSortedKeys
                                             error:error];
}

BOOL IrisImportAppearance(NSData *data, NSError **error) {
    if (!data.length || data.length > 65536) return IrisFail(error, @"Choose an appearance file under 64 KiB.");
    id parsed = [NSJSONSerialization JSONObjectWithData:data options:0 error:error];
    if (!parsed) return NO;
    if (![parsed isKindOfClass:NSDictionary.class]) return IrisFail(error, @"Choose an Iris appearance file.");
    NSDictionary *document = parsed;
    if (![document[@"format"] isEqual:@"iris-appearance"] || ![document[@"version"] isEqual:@1] ||
        ![document[@"values"] isKindOfClass:NSDictionary.class]) {
        return IrisFail(error, @"This file uses an unsupported appearance format.");
    }
    return IrisApplyAppearance(document[@"values"], NO, error);
}

static BOOL IrisApplyAppearance(NSDictionary *values, BOOL replace, NSError **error) {
    NSMutableDictionary *validated = [NSMutableDictionary dictionary];
    NSDictionary *fallbacks = IrisAppearanceDefaults();
    for (NSString *key in fallbacks) {
        id value = values[key];
        if (!value) continue;
        id normalized = IrisNormalizedValue(key, value);
        if (!normalized) return IrisFail(error, @"An appearance setting in this file is invalid.");
        validated[key] = normalized;
    }
    if (!validated.count) return IrisFail(error, @"This file has no supported appearance settings.");
    if (replace) {
        NSMutableDictionary *replacement = [fallbacks mutableCopy];
        [replacement addEntriesFromDictionary:validated];
        IrisSaveAppearance(replacement);
    } else {
        IrisSaveAppearance(validated);
    }
    return YES;
}

NSString *IrisExportAppearanceQR(NSError **error) {
    NSData *json = [NSJSONSerialization dataWithJSONObject:@{@"v": @1, @"d": IrisAppearancePreferences()}
                                                   options:NSJSONWritingSortedKeys error:error];
    if (!json) return nil;
    const size_t headerSize = sizeof(IrisTransferMagic) - 1;
    size_t capacity = ZSTD_compressBound(json.length);
    NSMutableData *payload = [NSMutableData dataWithLength:headerSize + capacity];
    char *bytes = payload.mutableBytes;
    memcpy(bytes, IrisTransferMagic, headerSize);
    size_t size = ZSTD_compress(bytes + headerSize, capacity, json.bytes, json.length, 19);
    if (ZSTD_isError(size)) {
        IrisFail(error, @"The appearance settings could not be compressed.");
        return nil;
    }
    payload.length = headerSize + size;
    NSString *text = [payload base64EncodedStringWithOptions:0];
    if (text.length <= IrisQRTextLimit) return text;
    IrisFail(error, @"The appearance settings are too large for a QR code.");
    return nil;
}

BOOL IrisImportAppearanceQR(NSString *text, NSError **error) {
    if (!text.length || text.length > IrisQRTextLimit) return IrisFail(error, @"Choose an Iris settings QR code.");
    NSData *payload = [[NSData alloc] initWithBase64EncodedString:text options:0];
    const size_t headerSize = sizeof(IrisTransferMagic) - 1;
    const char *bytes = payload.bytes;
    if (payload.length <= headerSize || memcmp(bytes, IrisTransferMagic, headerSize) != 0) {
        return IrisFail(error, @"Choose an Iris settings QR code.");
    }
    const char *frame = bytes + headerSize;
    size_t frameSize = payload.length - headerSize;
    if (ZSTD_findFrameCompressedSize(frame, frameSize) != frameSize) {
        return IrisFail(error, @"The Iris settings QR code is incomplete or damaged.");
    }
    unsigned long long size = ZSTD_getFrameContentSize(frame, frameSize);
    if (!size || size > IrisTransferLimit) return IrisFail(error, @"The Iris settings QR code has an invalid size.");
    NSMutableData *json = [NSMutableData dataWithLength:(NSUInteger)size];
    if (ZSTD_decompress(json.mutableBytes, json.length, frame, frameSize) != size) {
        return IrisFail(error, @"The Iris settings QR code could not be decompressed.");
    }
    id parsed = [NSJSONSerialization JSONObjectWithData:json options:0 error:error];
    if (!parsed) return NO;
    if (![parsed isKindOfClass:NSDictionary.class] || ![parsed[@"v"] isEqual:@1] ||
        ![parsed[@"d"] isKindOfClass:NSDictionary.class]) {
        return IrisFail(error, @"This QR code uses an unsupported Iris settings format.");
    }
    return IrisApplyAppearance(parsed[@"d"], YES, error);
}
