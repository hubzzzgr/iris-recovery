#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT NSNotificationName const IrisPreferencesDidChange;
FOUNDATION_EXPORT NSString *const IrisHeaderEnabled;
FOUNDATION_EXPORT NSString *const IrisHeaderSubtitleEnabled;
FOUNDATION_EXPORT NSString *const IrisHeaderTitle;
FOUNDATION_EXPORT NSString *const IrisHeaderSubtitle;
FOUNDATION_EXPORT NSString *const IrisHeaderColorHex;
FOUNDATION_EXPORT NSString *const IrisSubtitleColorHex;
FOUNDATION_EXPORT NSString *const IrisSwitchColorHex;
FOUNDATION_EXPORT NSString *const IrisRainbowRefresh;
FOUNDATION_EXPORT NSString *const IrisRainbowStyle;
FOUNDATION_EXPORT NSString *const IrisRefreshIndicatorColorHex;
FOUNDATION_EXPORT NSString *const IrisRainbowFirstColorHex;
FOUNDATION_EXPORT NSString *const IrisRainbowSecondColorHex;
FOUNDATION_EXPORT NSString *const IrisRainbowThirdColorHex;

NSDictionary<NSString *, id> *IrisAppearancePreferences(void);
NSArray<NSString *> *IrisRainbowStyles(void);
BOOL IrisSetAppearanceValue(NSString *key, id value, NSError *_Nullable *_Nullable error);
NSData *_Nullable IrisExportAppearance(NSError *_Nullable *_Nullable error);
BOOL IrisImportAppearance(NSData *data, NSError *_Nullable *_Nullable error);
NSString *_Nullable IrisExportAppearanceQR(NSError *_Nullable *_Nullable error);
BOOL IrisImportAppearanceQR(NSString *text, NSError *_Nullable *_Nullable error);

NS_ASSUME_NONNULL_END
