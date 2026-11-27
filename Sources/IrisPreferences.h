#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT NSNotificationName const IrisPreferencesDidChange;
FOUNDATION_EXPORT NSString *const IrisHeaderEnabled;
FOUNDATION_EXPORT NSString *const IrisHeaderSubtitleEnabled;
FOUNDATION_EXPORT NSString *const IrisHeaderTitle;
FOUNDATION_EXPORT NSString *const IrisHeaderSubtitle;
FOUNDATION_EXPORT NSString *const IrisHeaderColorHex;

NSDictionary<NSString *, id> *IrisAppearancePreferences(void);
BOOL IrisSetAppearanceValue(NSString *key, id value, NSError *_Nullable *_Nullable error);
NSData *_Nullable IrisExportAppearance(NSError *_Nullable *_Nullable error);
BOOL IrisImportAppearance(NSData *data, NSError *_Nullable *_Nullable error);

NS_ASSUME_NONNULL_END
