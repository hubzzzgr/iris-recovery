#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <string.h>

#import "IrisPreferences.h"
#import "IrisRefresh.h"
#import "IrisSettingsViewController.h"

@interface IrisHeaderAccessory : UIView
- (void)refreshAppearance;
@end

@implementation IrisHeaderAccessory {
    UILabel *_title;
    UILabel *_subtitle;
    UIButton *_settings;
}

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (!self) return nil;
    self.backgroundColor = UIColor.clearColor;
    _title = [UILabel new];
    _title.font = [UIFont preferredFontForTextStyle:UIFontTextStyleHeadline];
    _title.adjustsFontForContentSizeCategory = YES;
    _title.textAlignment = NSTextAlignmentCenter;
    _subtitle = [UILabel new];
    _subtitle.font = [UIFont preferredFontForTextStyle:UIFontTextStyleCaption1];
    _subtitle.adjustsFontForContentSizeCategory = YES;
    _subtitle.textAlignment = NSTextAlignmentCenter;
    _settings = [UIButton buttonWithType:UIButtonTypeSystem];
    [_settings setImage:[UIImage systemImageNamed:@"gearshape"] forState:UIControlStateNormal];
    _settings.accessibilityLabel = @"Iris settings menu";
    [_settings addTarget:self action:@selector(openSettings) forControlEvents:UIControlEventTouchUpInside];
    [self addSubview:_title];
    [self addSubview:_subtitle];
    [self addSubview:_settings];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(preferencesChanged:)
                                               name:IrisPreferencesDidChange object:nil];
    [self refreshAppearance];
    return self;
}

- (void)preferencesChanged:(NSNotification *)notification {
    (void)notification;
    [self refreshAppearance];
}

- (void)refreshAppearance {
    NSDictionary *values = IrisAppearancePreferences();
    BOOL showHeader = [values[IrisHeaderEnabled] boolValue];
    _title.text = showHeader ? values[IrisHeaderTitle] : nil;
    _subtitle.text = showHeader && [values[IrisHeaderSubtitleEnabled] boolValue] ? values[IrisHeaderSubtitle] : nil;
    UIColor *color = IrisColorFromHex(values[IrisHeaderColorHex]);
    _title.textColor = color ?: UIColor.labelColor;
    _subtitle.textColor = IrisColorFromHex(values[IrisSubtitleColorHex]) ?: UIColor.secondaryLabelColor;
    _settings.tintColor = color ?: UIColor.labelColor;
    [self setNeedsLayout];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat width = CGRectGetWidth(self.bounds);
    CGFloat height = CGRectGetHeight(self.bounds);
    CGFloat textWidth = MAX(0, width - 44.0);
    _settings.frame = CGRectMake(textWidth, 0, width - textWidth, height);
    CGFloat titleHeight = _subtitle.text.length ? height * 0.62 : height;
    _title.frame = CGRectMake(0, 0, textWidth, titleHeight);
    _subtitle.frame = CGRectMake(0, titleHeight, textWidth, height - titleHeight);
}

- (BOOL)pointInside:(CGPoint)point withEvent:(UIEvent *)event {
    return [super pointInside:point withEvent:event] && CGRectContainsPoint(_settings.frame, point);
}

- (void)openSettings {
    UIViewController *top = self.window.rootViewController;
    if (!top) return;
    while (top.presentedViewController && !top.presentedViewController.isBeingDismissed) {
        top = top.presentedViewController;
    }
    if (top.isBeingDismissed || top.isBeingPresented) return;
    if ([top isKindOfClass:UINavigationController.class]) {
        UINavigationController *navigation = (UINavigationController *)top;
        if ([navigation.topViewController isKindOfClass:IrisSettingsViewController.class]) return;
    }
    IrisSettingsViewController *settings = [IrisSettingsViewController new];
    UINavigationController *navigation = [[UINavigationController alloc] initWithRootViewController:settings];
    [top presentViewController:navigation animated:YES completion:nil];
}

@end

static char IrisAccessoryKey;
static IMP IrisOriginalLayout;
static IMP IrisOriginalMove;
static IMP IrisOriginalTraits;
static IMP IrisOriginalTransition;
static IMP IrisOriginalHitTest;

static void IrisUpdateHeader(UIView *header) {
    if (!NSThread.isMainThread) return;
    IrisHeaderAccessory *overlay = objc_getAssociatedObject(header, &IrisAccessoryKey);
    CGFloat width = CGRectGetWidth(header.bounds);
    CGFloat height = CGRectGetHeight(header.bounds);
    if (!header.window || width < 60.0 || height < 30.0) {
        overlay.hidden = YES;
        return;
    }
    if (!overlay) {
        overlay = [[IrisHeaderAccessory alloc] initWithFrame:CGRectZero];
        objc_setAssociatedObject(header, &IrisAccessoryKey, overlay, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    if (overlay.superview != header) [header addSubview:overlay];
    CGFloat accessoryWidth = MIN(width * 0.48, 212.0);
    CGFloat accessoryHeight = MIN(height, 50.0);
    overlay.frame = CGRectMake(CGRectGetMidX(header.bounds) - accessoryWidth * 0.5,
                               CGRectGetMidY(header.bounds) - accessoryHeight * 0.5,
                               accessoryWidth, accessoryHeight);
    overlay.hidden = NO;
}

static void IrisLayout(UIView *header, SEL selector) {
    ((void (*)(UIView *, SEL))IrisOriginalLayout)(header, selector);
    IrisUpdateHeader(header);
}

static void IrisDidMoveToWindow(UIView *header, SEL selector) {
    ((void (*)(UIView *, SEL))IrisOriginalMove)(header, selector);
    IrisUpdateHeader(header);
}

static void IrisTraitsChanged(UIView *header, SEL selector, UITraitCollection *previous) {
    ((void (*)(UIView *, SEL, id))IrisOriginalTraits)(header, selector, previous);
    IrisUpdateHeader(header);
}

static void IrisTransition(UIView *header, SEL selector, id item) {
    ((void (*)(UIView *, SEL, id))IrisOriginalTransition)(header, selector, item);
    IrisUpdateHeader(header);
}

static UIView *IrisHitTest(UIView *header, SEL selector, CGPoint point, UIEvent *event) {
    IrisHeaderAccessory *overlay = objc_getAssociatedObject(header, &IrisAccessoryKey);
    if (header.userInteractionEnabled && !header.hidden && header.alpha > 0.01 &&
        overlay.superview == header && overlay.window) {
        UIView *hit = [overlay hitTest:[overlay convertPoint:point fromView:header] withEvent:event];
        if (hit && hit != overlay) return hit;
    }
    return ((UIView *(*)(UIView *, SEL, CGPoint, UIEvent *))IrisOriginalHitTest)(header, selector, point, event);
}

// Install on the subclass so inherited UIView implementations remain shared by other views.
static void IrisInstallMethod(Class cls, SEL selector, IMP replacement, unsigned arguments, IMP *original) {
    if (*original) return;
    Method method = class_getInstanceMethod(cls, selector);
    if (!method || method_getNumberOfArguments(method) != arguments) return;
    char type[64] = {0};
    method_getReturnType(method, type, sizeof(type));
    if (selector == @selector(hitTest:withEvent:)) {
        if (type[0] != '@') return;
        method_getArgumentType(method, 2, type, sizeof(type));
        if (strcmp(type, @encode(CGPoint)) != 0) return;
        method_getArgumentType(method, 3, type, sizeof(type));
        if (type[0] != '@') return;
    } else if (strcmp(type, "v") != 0) {
        return;
    } else if (arguments == 3) {
        method_getArgumentType(method, 2, type, sizeof(type));
        if (type[0] != '@') return;
    }
    const char *encoding = method_getTypeEncoding(method);
    *original = method_getImplementation(method);
    if (class_addMethod(cls, selector, replacement, encoding)) return;
    IMP previous = class_replaceMethod(cls, selector, replacement, encoding);
    if (previous) *original = previous;
}

static BOOL IrisInstallHeader(void) {
    Class header = NSClassFromString(@"SIGHeader");
    if (!header || ![header isSubclassOfClass:UIView.class]) return NO;
    IrisInstallMethod(header, @selector(layoutSubviews), (IMP)IrisLayout, 2, &IrisOriginalLayout);
    IrisInstallMethod(header, @selector(didMoveToWindow), (IMP)IrisDidMoveToWindow, 2, &IrisOriginalMove);
    IrisInstallMethod(header, @selector(traitCollectionDidChange:), (IMP)IrisTraitsChanged, 3, &IrisOriginalTraits);
    IrisInstallMethod(header, NSSelectorFromString(@"setUpAnimatedTransitionToHeaderItem:"),
                      (IMP)IrisTransition, 3, &IrisOriginalTransition);
    IrisInstallMethod(header, @selector(hitTest:withEvent:), (IMP)IrisHitTest, 4, &IrisOriginalHitTest);
    IrisInstallRefreshAppearance();
    return IrisOriginalLayout != NULL;
}

@interface IrisHeaderLoader : NSObject
+ (void)applicationDidBecomeActive:(NSNotification *)notification;
@end

@implementation IrisHeaderLoader
+ (void)applicationDidBecomeActive:(NSNotification *)notification {
    (void)notification;
    if (IrisInstallHeader()) {
        [NSNotificationCenter.defaultCenter removeObserver:self name:UIApplicationDidBecomeActiveNotification object:nil];
    }
}
@end

__attribute__((constructor))
static void IrisStart(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (!IrisInstallHeader()) {
            [NSNotificationCenter.defaultCenter addObserver:IrisHeaderLoader.class
                selector:@selector(applicationDidBecomeActive:) name:UIApplicationDidBecomeActiveNotification object:nil];
        }
    });
}
