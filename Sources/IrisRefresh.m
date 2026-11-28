#import "IrisRefresh.h"
#import "IrisPreferences.h"
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>
#include <float.h>

UIColor *IrisColorFromHex(NSString *hex) {
    unsigned rgb = 0;
    if (hex.length != 7 || ![[NSScanner scannerWithString:[hex substringFromIndex:1]] scanHexInt:&rgb]) return nil;
    return [UIColor colorWithRed:((rgb >> 16) & 255) / 255.0 green:((rgb >> 8) & 255) / 255.0
                             blue:(rgb & 255) / 255.0 alpha:1.0];
}

static NSArray *IrisGradientColors(NSDictionary *settings) {
    NSDictionary *palettes = @{
        @"classic": @[@"#FF4F78", @"#FFE165", @"#40DFBC", @"#647AFF", @"#CC66FF"],
        @"sunset": @[@"#FF595E", @"#FFAD57", @"#C760DA"],
        @"ocean": @[@"#25D9C7", @"#52B7FA", @"#3860D6"],
        @"aurora": @[@"#69E6A2", @"#2DC8C7", @"#A77BF8"],
        @"candy": @[@"#FF83B5", @"#9B86FF", @"#6BDFF0"],
        @"custom": @[settings[IrisRainbowFirstColorHex], settings[IrisRainbowSecondColorHex], settings[IrisRainbowThirdColorHex]],
    };
    NSArray<NSString *> *hexes = palettes[settings[IrisRainbowStyle]];
    NSArray<NSString *> *defaultColors = palettes[@"classic"];
    NSMutableArray *colors = [NSMutableArray arrayWithCapacity:hexes.count + 1];
    for (NSUInteger index = 0; index < hexes.count; index++) {
        UIColor *color = IrisColorFromHex(hexes[index]) ?: IrisColorFromHex(defaultColors[index]);
        [colors addObject:(__bridge id)color.CGColor];
    }
    [colors addObject:colors.firstObject];
    return colors;
}

@interface IrisRefreshAppearance : NSObject
@property (nonatomic, strong) CAGradientLayer *gradient;
@property (nonatomic, strong) UIColor *oldTint;
@property (nonatomic, strong) UIColor *irisTint;
@end

@implementation IrisRefreshAppearance
@end

static char IrisRefreshAppearanceKey;
static IMP IrisOriginalRefreshLayout;
static NSDictionary *IrisRefreshSettings;
static NSArray *IrisRefreshColors;

static void IrisLayoutRefresh(UIRefreshControl *control, SEL selector) {
    ((void (*)(UIRefreshControl *, SEL))IrisOriginalRefreshLayout)(control, selector);
    BOOL rainbow = [IrisRefreshSettings[IrisRainbowRefresh] boolValue] && CGRectGetWidth(control.bounds) >= 60 &&
                   CGRectGetHeight(control.bounds) >= 38;
    UIColor *tint = IrisColorFromHex(IrisRefreshSettings[IrisRefreshIndicatorColorHex]);
    IrisRefreshAppearance *appearance = objc_getAssociatedObject(control, &IrisRefreshAppearanceKey);
    if (!appearance && !rainbow && !tint) return;
    if (!appearance) {
        appearance = [IrisRefreshAppearance new];
        objc_setAssociatedObject(control, &IrisRefreshAppearanceKey, appearance, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    if (tint) {
        if (![control.tintColor isEqual:appearance.irisTint]) appearance.oldTint = control.tintColor;
        appearance.irisTint = tint;
        if (![control.tintColor isEqual:tint]) control.tintColor = tint;
    } else if (appearance.irisTint) {
        if ([control.tintColor isEqual:appearance.irisTint]) control.tintColor = appearance.oldTint;
        appearance.irisTint = nil;
        appearance.oldTint = nil;
    }
    if (!rainbow) {
        [appearance.gradient removeFromSuperlayer];
        appearance.gradient = nil;
        return;
    }
    if (!appearance.gradient) {
        appearance.gradient = [CAGradientLayer layer];
        appearance.gradient.startPoint = CGPointMake(0, 0.5);
        appearance.gradient.endPoint = CGPointMake(1, 0.5);
        appearance.gradient.cornerRadius = 2;
        [control.layer addSublayer:appearance.gradient];
    }
    CAGradientLayer *gradient = appearance.gradient;
    NSArray *colors = IrisRefreshColors;
    BOOL newPalette = ![gradient.colors isEqual:colors];
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    gradient.frame = CGRectMake(CGRectGetMidX(control.bounds) - 28, CGRectGetMidY(control.bounds) + 16, 56, 4);
    gradient.colors = colors;
    [CATransaction commit];
    if (newPalette || !control.isRefreshing || UIAccessibilityIsReduceMotionEnabled()) {
        [gradient removeAnimationForKey:@"iris.colors"];
    }
    if (control.isRefreshing && !UIAccessibilityIsReduceMotionEnabled() && ![gradient animationForKey:@"iris.colors"]) {
        CABasicAnimation *animation = [CABasicAnimation animationWithKeyPath:@"colors"];
        animation.fromValue = colors;
        animation.toValue = [[colors reverseObjectEnumerator] allObjects];
        animation.duration = 0.9;
        animation.autoreverses = YES;
        animation.repeatCount = FLT_MAX;
        [gradient addAnimation:animation forKey:@"iris.colors"];
    }
}

void IrisInstallRefreshAppearance(void) {
    if (IrisOriginalRefreshLayout) return;
    Class control = UIRefreshControl.class;
    SEL selector = @selector(layoutSubviews);
    Method method = class_getInstanceMethod(control, selector);
    if (!method) return;
    const char *encoding = method_getTypeEncoding(method);
    IrisOriginalRefreshLayout = method_getImplementation(method);
    if (!class_addMethod(control, selector, (IMP)IrisLayoutRefresh, encoding)) {
        IMP previous = class_replaceMethod(control, selector, (IMP)IrisLayoutRefresh, encoding);
        if (previous) IrisOriginalRefreshLayout = previous;
    }
    IrisRefreshSettings = IrisAppearancePreferences();
    IrisRefreshColors = IrisGradientColors(IrisRefreshSettings);
    [NSNotificationCenter.defaultCenter addObserverForName:IrisPreferencesDidChange object:nil
        queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note) {
            (void)note;
            IrisRefreshSettings = IrisAppearancePreferences();
            IrisRefreshColors = IrisGradientColors(IrisRefreshSettings);
        }];
}

@interface IrisRefreshPreview : UIViewController
@end

@implementation IrisRefreshPreview

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Pull to Refresh";
    self.view.backgroundColor = UIColor.systemGroupedBackgroundColor;
    UIScrollView *scroll = [[UIScrollView alloc] initWithFrame:self.view.bounds];
    scroll.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    scroll.alwaysBounceVertical = YES;
    UIRefreshControl *refresh = [UIRefreshControl new];
    [refresh addTarget:self action:@selector(refreshPreview:) forControlEvents:UIControlEventValueChanged];
    scroll.refreshControl = refresh;
    UILabel *instruction = [UILabel new];
    instruction.text = @"Pull down to preview the refresh indicator.";
    instruction.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
    instruction.adjustsFontForContentSizeCategory = YES;
    instruction.textAlignment = NSTextAlignmentCenter;
    instruction.numberOfLines = 0;
    instruction.translatesAutoresizingMaskIntoConstraints = NO;
    [scroll addSubview:instruction];
    [self.view addSubview:scroll];
    [NSLayoutConstraint activateConstraints:@[
        [instruction.widthAnchor constraintEqualToAnchor:scroll.frameLayoutGuide.widthAnchor constant:-48],
        [instruction.leadingAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.leadingAnchor constant:24],
        [instruction.trailingAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.trailingAnchor constant:-24],
        [instruction.topAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.topAnchor constant:36],
        [instruction.bottomAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.bottomAnchor constant:-36],
    ]];
}

- (void)refreshPreview:(UIRefreshControl *)refresh {
    [refresh setNeedsLayout];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        [refresh endRefreshing];
        [refresh setNeedsLayout];
    });
}

@end

UIViewController *IrisMakeRefreshPreview(void) {
    IrisInstallRefreshAppearance();
    return [IrisRefreshPreview new];
}
