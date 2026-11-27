#import "IrisPreferences.h"
#import <CoreFoundation/CoreFoundation.h>

NSNotificationName const IrisPreferencesDidChange = @"IrisPreferencesDidChange";
NSString *const IrisHeaderEnabled = @"iris_header_enabled";
NSString *const IrisHeaderSubtitleEnabled = @"iris_header_subtitle_enabled";
NSString *const IrisHeaderTitle = @"iris_custom_header_title";
NSString *const IrisHeaderSubtitle = @"iris_custom_header_subtitle";
NSString *const IrisHeaderColorHex = @"iris_header_color_hex";

static NSDictionary<NSString *, id> *IrisAppearanceDefaults(void) {
    return @{
        IrisHeaderEnabled: @YES, IrisHeaderSubtitleEnabled: @NO,
        IrisHeaderTitle: @"Iris", IrisHeaderSubtitle: @"", IrisHeaderColorHex: @"",
    };
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
    if ([key isEqualToString:IrisHeaderColorHex]) {
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
    NSMutableDictionary *values = [IrisAppearanceDefaults() mutableCopy];
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    for (NSString *key in IrisAppearanceDefaults()) {
        id value = IrisNormalizedValue(key, [defaults objectForKey:key]);
        if (value) values[key] = value;
    }
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
        NSString *message = [key isEqualToString:IrisHeaderColorHex]
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
    NSDictionary *values = document[@"values"];
    NSMutableDictionary *validated = [NSMutableDictionary dictionary];
    for (NSString *key in IrisAppearanceDefaults()) {
        id value = values[key];
        if (!value) continue;
        id normalized = IrisNormalizedValue(key, value);
        if (!normalized) return IrisFail(error, @"An appearance setting in this file is invalid.");
        validated[key] = normalized;
    }
    if (!validated.count) return IrisFail(error, @"This file has no supported appearance settings.");
    IrisSaveAppearance(validated);
    return YES;
}
