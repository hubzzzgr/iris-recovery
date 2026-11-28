#import "IrisSettingsViewController.h"
#import "IrisMediaViewController.h"
#import "IrisPreferences.h"
#import "IrisRefresh.h"
#import <CoreImage/CoreImage.h>
#import <PhotosUI/PhotosUI.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

@interface IrisSettingsViewController () <UIDocumentPickerDelegate, PHPickerViewControllerDelegate>
@end

typedef NS_ENUM(NSInteger, IrisSettingsSection) {
    IrisSettingsAppearance,
    IrisSettingsRefresh,
    IrisSettingsMedia,
    IrisSettingsPrivacy,
    IrisSettingsTransfer,
    IrisSettingsIcon,
};

typedef NS_ENUM(NSInteger, IrisRefreshRow) {
    IrisRefreshRainbow,
    IrisRefreshPalette,
    IrisRefreshTint,
    IrisRefreshPreviewRow,
    IrisRefreshFirstColor,
    IrisRefreshSecondColor,
    IrisRefreshThirdColor,
};

static NSArray<NSString *> *IrisAppearanceLabels(void) {
    return @[@"Custom header", @"Show subtitle", @"Title", @"Subtitle", @"Title color", @"Subtitle color", @"Switch color"];
}

static NSArray<NSString *> *IrisAppearanceKeys(void) {
    return @[IrisHeaderEnabled, IrisHeaderSubtitleEnabled, IrisHeaderTitle, IrisHeaderSubtitle,
             IrisHeaderColorHex, IrisSubtitleColorHex, IrisSwitchColorHex];
}

static NSArray<NSString *> *IrisRefreshLabels(void) {
    return @[@"Rainbow effect", @"Rainbow palette", @"Spinner color", @"Preview effect",
             @"First color", @"Second color", @"Third color"];
}

static NSString *IrisRefreshColorKey(NSInteger row) {
    if (row == IrisRefreshTint) return IrisRefreshIndicatorColorHex;
    return (@[IrisRainbowFirstColorHex, IrisRainbowSecondColorHex, IrisRainbowThirdColorHex])[row - IrisRefreshFirstColor];
}

static NSString *const IrisAlternateIcon = @"icon_iris2";

static BOOL IrisHasAlternateIcon(void) {
    UIApplication *app = UIApplication.sharedApplication;
    if (!app.supportsAlternateIcons) return NO;
    NSDictionary *info = NSBundle.mainBundle.infoDictionary;
    return info[@"CFBundleIcons"][@"CFBundleAlternateIcons"][IrisAlternateIcon] != nil ||
           (UIDevice.currentDevice.userInterfaceIdiom == UIUserInterfaceIdiomPad &&
            info[@"CFBundleIcons~ipad"][@"CFBundleAlternateIcons"][IrisAlternateIcon] != nil);
}

@implementation IrisSettingsViewController

- (instancetype)init {
    return [super initWithStyle:UITableViewStyleInsetGrouped];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Iris Settings";
    self.navigationItem.rightBarButtonItem =
        [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone
                                                     target:self action:@selector(closeSettings)];
}

- (void)closeSettings {
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    (void)tableView;
    return IrisSettingsIcon + (IrisHasAlternateIcon() ? 1 : 0);
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    (void)tableView;
    if (section == IrisSettingsAppearance) return IrisAppearanceKeys().count;
    if (section == IrisSettingsTransfer) return 4;
    if (section == IrisSettingsRefresh) {
        return [IrisAppearancePreferences()[IrisRainbowStyle] isEqual:@"custom"] ? IrisRefreshThirdColor + 1 : IrisRefreshPreviewRow + 1;
    }
    return 1;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    (void)tableView;
    return (@[@"Appearance", @"Pull to Refresh", @"Media", @"Privacy", @"Transfer Settings", @"App Icon"])[section];
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)path {
    (void)tableView;
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:nil];
    if (path.section == IrisSettingsTransfer) {
        cell.textLabel.text = (@[@"Import JSON file", @"Export JSON file", @"Import QR from Photos", @"Show settings QR"])[path.row];
        cell.textLabel.textColor = UIColor.systemBlueColor;
        return cell;
    }
    if (path.section == IrisSettingsIcon) {
        BOOL selected = [UIApplication.sharedApplication.alternateIconName isEqualToString:IrisAlternateIcon];
        cell.textLabel.text = selected ? @"Restore default icon" : @"Use Iris icon";
        cell.textLabel.textColor = UIColor.systemBlueColor;
        return cell;
    }
    if (path.section == IrisSettingsRefresh) {
        [self configureRefreshCell:cell row:path.row];
        return cell;
    }
    if (path.section == IrisSettingsMedia || path.section == IrisSettingsPrivacy) {
        cell.textLabel.text = path.section == IrisSettingsMedia ? @"Save and export files" : @"App permissions in Settings";
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        return cell;
    }
    NSArray *labels = IrisAppearanceLabels();
    NSArray *keys = IrisAppearanceKeys();
    NSDictionary *values = IrisAppearancePreferences();
    id value = values[keys[path.row]];
    cell.textLabel.text = labels[path.row];
    if (path.row < 2) {
        UISwitch *toggle = [UISwitch new];
        toggle.on = [value boolValue];
        toggle.onTintColor = IrisColorFromHex(values[IrisSwitchColorHex]);
        toggle.tag = path.row;
        toggle.accessibilityLabel = labels[path.row];
        [toggle addTarget:self action:@selector(toggleChanged:) forControlEvents:UIControlEventValueChanged];
        cell.accessoryView = toggle;
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
    } else {
        cell.detailTextLabel.text = [value length] ? value : (path.row >= 4 ? @"Default" : @"");
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    }
    return cell;
}

- (void)configureRefreshCell:(UITableViewCell *)cell row:(NSInteger)row {
    NSDictionary *preferences = IrisAppearancePreferences();
    cell.textLabel.text = IrisRefreshLabels()[row];
    if (row == IrisRefreshRainbow) {
        UISwitch *toggle = [UISwitch new];
        toggle.on = [preferences[IrisRainbowRefresh] boolValue];
        toggle.onTintColor = IrisColorFromHex(preferences[IrisSwitchColorHex]);
        toggle.accessibilityLabel = cell.textLabel.text;
        [toggle addTarget:self action:@selector(rainbowChanged:) forControlEvents:UIControlEventValueChanged];
        cell.accessoryView = toggle;
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        return;
    }
    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    if (row == IrisRefreshPalette) {
        cell.detailTextLabel.text = [preferences[IrisRainbowStyle] capitalizedString];
    } else if (row != IrisRefreshPreviewRow) {
        NSString *hex = preferences[IrisRefreshColorKey(row)];
        cell.detailTextLabel.text = hex.length ? hex : @"Default";
    }
}

- (void)rainbowChanged:(UISwitch *)sender {
    IrisSetAppearanceValue(IrisRainbowRefresh, @(sender.on), NULL);
}

- (void)toggleChanged:(UISwitch *)sender {
    IrisSetAppearanceValue(sender.tag == 0 ? IrisHeaderEnabled : IrisHeaderSubtitleEnabled, @(sender.on), NULL);
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)path {
    [tableView deselectRowAtIndexPath:path animated:YES];
    if (path.section == IrisSettingsTransfer) {
        UIView *anchor = [tableView cellForRowAtIndexPath:path] ?: tableView;
        switch (path.row) {
            case 0: [self chooseAppearanceFile]; break;
            case 1: [self exportAppearanceFromView:anchor]; break;
            case 2: [self chooseQRImage]; break;
            case 3: [self showQR]; break;
        }
        return;
    }
    if (path.section == IrisSettingsIcon) {
        [self toggleAlternateIcon];
        return;
    }
    if (path.section == IrisSettingsMedia) {
        [self.navigationController pushViewController:[IrisMediaViewController new] animated:YES];
        return;
    }
    if (path.section == IrisSettingsPrivacy) {
        [UIApplication.sharedApplication openURL:[NSURL URLWithString:UIApplicationOpenSettingsURLString]
                                         options:@{} completionHandler:nil];
        return;
    }
    if (path.section == IrisSettingsRefresh) {
        if (path.row == IrisRefreshPalette) [self chooseRainbowPaletteFromView:[tableView cellForRowAtIndexPath:path] ?: tableView];
        else if (path.row == IrisRefreshPreviewRow) [self.navigationController pushViewController:IrisMakeRefreshPreview() animated:YES];
        else if (path.row != IrisRefreshRainbow) [self editPreference:IrisRefreshColorKey(path.row) label:IrisRefreshLabels()[path.row]];
        return;
    }
    if (path.row < 2) return;
    [self editPreference:IrisAppearanceKeys()[path.row] label:IrisAppearanceLabels()[path.row]];
}

- (void)chooseRainbowPaletteFromView:(UIView *)anchor {
    UIAlertController *menu = [UIAlertController alertControllerWithTitle:@"Rainbow palette" message:nil preferredStyle:UIAlertControllerStyleActionSheet];
    __weak typeof(self) weakSelf = self;
    for (NSString *palette in IrisRainbowStyles()) {
        [menu addAction:[UIAlertAction actionWithTitle:palette.capitalizedString style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
            (void)action;
            IrisSetAppearanceValue(IrisRainbowStyle, palette, NULL);
            [weakSelf.tableView reloadData];
        }]];
    }
    [menu addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    menu.popoverPresentationController.sourceView = anchor;
    menu.popoverPresentationController.sourceRect = anchor.bounds;
    [self presentViewController:menu animated:YES completion:nil];
}

- (void)editPreference:(NSString *)key label:(NSString *)label {
    BOOL isColor = [key hasSuffix:@"_hex"];
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:label
        message:isColor ? @"Enter a hex color such as #34A5EF." : nil preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *field) {
        field.text = IrisAppearancePreferences()[key];
        field.clearButtonMode = UITextFieldViewModeWhileEditing;
        if (isColor) {
            field.autocorrectionType = UITextAutocorrectionTypeNo;
            field.autocapitalizationType = UITextAutocapitalizationTypeAllCharacters;
        }
    }];
    UITextField *field = alert.textFields.firstObject;
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    __weak typeof(self) weakSelf = self;
    [alert addAction:[UIAlertAction actionWithTitle:@"Save" style:UIAlertActionStyleDefault
                                           handler:^(UIAlertAction *action) {
        (void)action;
        NSError *error = nil;
        if (IrisSetAppearanceValue(key, field.text ?: @"", &error)) {
            [weakSelf.tableView reloadData];
        } else {
            dispatch_async(dispatch_get_main_queue(), ^{ [weakSelf showError:error]; });
        }
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)toggleAlternateIcon {
    UIApplication *app = UIApplication.sharedApplication;
    if (!IrisHasAlternateIcon()) return;
    NSString *newIcon = [app.alternateIconName isEqualToString:IrisAlternateIcon] ? nil : IrisAlternateIcon;
    __weak typeof(self) weakSelf = self;
    [app setAlternateIconName:newIcon completionHandler:^(NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (error) [weakSelf showError:error];
            else [weakSelf.tableView reloadData];
        });
    }];
}

- (void)chooseQRImage {
    PHPickerConfiguration *configuration = [PHPickerConfiguration new];
    configuration.filter = PHPickerFilter.imagesFilter;
    PHPickerViewController *picker = [[PHPickerViewController alloc] initWithConfiguration:configuration];
    picker.delegate = self;
    [self presentViewController:picker animated:YES completion:nil];
}

- (void)picker:(PHPickerViewController *)picker didFinishPicking:(NSArray<PHPickerResult *> *)results {
    NSItemProvider *provider = results.firstObject.itemProvider;
    __weak typeof(self) weakSelf = self;
    [picker dismissViewControllerAnimated:YES completion:^{
        if (!provider) return;
        [provider loadObjectOfClass:UIImage.class completionHandler:^(UIImage *image, NSError *failure) {
            CIImage *input = image ? [[CIImage alloc] initWithImage:image] : nil;
            CIDetector *detector = [CIDetector detectorOfType:CIDetectorTypeQRCode context:nil
                                                    options:@{CIDetectorAccuracy: CIDetectorAccuracyHigh}];
            NSArray *features = input ? [detector featuresInImage:input] : nil;
            dispatch_async(dispatch_get_main_queue(), ^{
                NSError *error = failure;
                for (CIQRCodeFeature *feature in features) {
                    if (IrisImportAppearanceQR(feature.messageString ?: @"", &error)) {
                        [weakSelf.tableView reloadData];
                        return;
                    }
                }
                [weakSelf showError:error ?: [NSError errorWithDomain:@"IrisAppearance" code:2
                    userInfo:@{NSLocalizedDescriptionKey: @"No Iris settings QR code was found in that image."}]];
            });
        }];
    }];
}

- (void)showQR {
    NSError *error = nil;
    NSString *text = IrisExportAppearanceQR(&error);
    if (!text) {
        [self showError:error];
        return;
    }
    CIFilter *generator = [CIFilter filterWithName:@"CIQRCodeGenerator"];
    [generator setValue:[text dataUsingEncoding:NSASCIIStringEncoding] forKey:@"inputMessage"];
    [generator setValue:@"M" forKey:@"inputCorrectionLevel"];
    CIImage *code = generator.outputImage;
    if (!code) {
        [self showError:nil];
        return;
    }
    CIImage *scaled = [code imageByApplyingTransform:CGAffineTransformMakeScale(8, 8)];
    CGImageRef rendered = [[CIContext contextWithOptions:nil] createCGImage:scaled fromRect:scaled.extent];
    if (!rendered) {
        [self showError:nil];
        return;
    }
    UIImage *qr = [UIImage imageWithCGImage:rendered];
    CGImageRelease(rendered);
    UIGraphicsImageRendererFormat *format = [UIGraphicsImageRendererFormat defaultFormat];
    format.opaque = YES;
    format.scale = 1;
    const CGFloat border = 32;
    CGSize size = CGSizeMake(qr.size.width + border * 2, qr.size.height + border * 2);
    UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:size format:format];
    UIImage *image = [renderer imageWithActions:^(UIGraphicsImageRendererContext *context) {
        [UIColor.whiteColor setFill];
        [context fillRect:(CGRect){CGPointZero, size}];
        [qr drawAtPoint:CGPointMake(border, border)];
    }];
    UIViewController *preview = [UIViewController new];
    preview.title = @"Iris Settings QR";
    preview.view.backgroundColor = UIColor.systemBackgroundColor;
    UIImageView *imageView = [[UIImageView alloc] initWithImage:image];
    imageView.contentMode = UIViewContentModeScaleAspectFit;
    imageView.accessibilityLabel = @"Iris appearance settings QR code";
    imageView.isAccessibilityElement = YES;
    imageView.translatesAutoresizingMaskIntoConstraints = NO;
    [preview.view addSubview:imageView];
    UILayoutGuide *guide = preview.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [imageView.leadingAnchor constraintEqualToAnchor:guide.leadingAnchor constant:24],
        [imageView.trailingAnchor constraintEqualToAnchor:guide.trailingAnchor constant:-24],
        [imageView.topAnchor constraintEqualToAnchor:guide.topAnchor constant:24],
        [imageView.bottomAnchor constraintEqualToAnchor:guide.bottomAnchor constant:-24],
    ]];
    __weak UIViewController *weakPreview = preview;
    preview.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemAction
        primaryAction:[UIAction actionWithHandler:^(UIAction *action) {
            (void)action;
            UIViewController *presenter = weakPreview;
            UIActivityViewController *activity = [[UIActivityViewController alloc] initWithActivityItems:@[image] applicationActivities:nil];
            activity.popoverPresentationController.barButtonItem = presenter.navigationItem.rightBarButtonItem;
            [presenter presentViewController:activity animated:YES completion:nil];
        }]];
    [self.navigationController pushViewController:preview animated:YES];
}

- (void)chooseAppearanceFile {
    UIDocumentPickerViewController *picker =
        [[UIDocumentPickerViewController alloc] initForOpeningContentTypes:@[UTTypeJSON] asCopy:YES];
    picker.delegate = self;
    [self presentViewController:picker animated:YES completion:nil];
}

- (void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
    (void)controller;
    NSURL *url = urls.firstObject;
    if (!url) return;
    BOOL accessed = [url startAccessingSecurityScopedResource];
    NSError *error = nil;
    id size = nil;
    [url getResourceValue:&size forKey:NSURLFileSizeKey error:&error];
    NSData *data = [size isKindOfClass:NSNumber.class] && [size unsignedLongLongValue] <= 65536 && !error
        ? [NSData dataWithContentsOfURL:url options:0 error:&error] : nil;
    if (accessed) [url stopAccessingSecurityScopedResource];
    if (IrisImportAppearance(data ?: [NSData data], &error)) [self.tableView reloadData];
    else dispatch_async(dispatch_get_main_queue(), ^{ [self showError:error]; });
}

- (void)exportAppearanceFromView:(UIView *)anchor {
    NSError *error = nil;
    NSData *data = IrisExportAppearance(&error);
    if (!data) {
        [self showError:error];
        return;
    }
    NSURL *temp = [NSURL fileURLWithPath:NSTemporaryDirectory() isDirectory:YES];
    NSURL *directory = [temp URLByAppendingPathComponent:NSUUID.UUID.UUIDString isDirectory:YES];
    if (![NSFileManager.defaultManager createDirectoryAtURL:directory withIntermediateDirectories:NO attributes:nil error:&error]) {
        [self showError:error];
        return;
    }
    NSURL *url = [directory URLByAppendingPathComponent:@"Iris-Appearance.json"];
    if (![data writeToURL:url options:NSDataWritingAtomic error:&error]) {
        [NSFileManager.defaultManager removeItemAtURL:directory error:NULL];
        [self showError:error];
        return;
    }
    UIActivityViewController *activity = [[UIActivityViewController alloc] initWithActivityItems:@[url] applicationActivities:nil];
    activity.popoverPresentationController.sourceView = anchor;
    activity.popoverPresentationController.sourceRect = anchor.bounds;
    activity.completionWithItemsHandler = ^(UIActivityType type, BOOL completed, NSArray *items, NSError *failure) {
        (void)type; (void)completed; (void)items; (void)failure;
        [NSFileManager.defaultManager removeItemAtURL:directory error:NULL];
    };
    [self presentViewController:activity animated:YES completion:nil];
}

- (void)showError:(NSError *)error {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Appearance settings"
        message:error.localizedDescription ?: @"The operation could not be completed." preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

@end
