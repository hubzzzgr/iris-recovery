#import "IrisSettingsViewController.h"
#import "IrisPreferences.h"
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

@interface IrisSettingsViewController () <UIDocumentPickerDelegate>
@end

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
    return 2;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    (void)tableView;
    return section == 0 ? 5 : 2;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    (void)tableView;
    return section == 0 ? @"Header" : @"Appearance file";
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)path {
    (void)tableView;
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:nil];
    if (path.section == 1) {
        cell.textLabel.text = path.row == 0 ? @"Import appearance" : @"Export appearance";
        cell.textLabel.textColor = UIColor.systemBlueColor;
        return cell;
    }
    NSArray *labels = @[@"Custom header", @"Show subtitle", @"Title", @"Subtitle", @"Text color"];
    NSArray *keys = @[IrisHeaderEnabled, IrisHeaderSubtitleEnabled, IrisHeaderTitle, IrisHeaderSubtitle, IrisHeaderColorHex];
    id value = IrisAppearancePreferences()[keys[path.row]];
    cell.textLabel.text = labels[path.row];
    if (path.row < 2) {
        UISwitch *toggle = [UISwitch new];
        toggle.on = [value boolValue];
        toggle.tag = path.row;
        toggle.accessibilityLabel = labels[path.row];
        [toggle addTarget:self action:@selector(toggleChanged:) forControlEvents:UIControlEventValueChanged];
        cell.accessoryView = toggle;
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
    } else {
        cell.detailTextLabel.text = [value length] ? value : (path.row == 4 ? @"Default" : @"");
        cell.accessoryType = UITableViewCellAccessoryTypeDisclosureIndicator;
    }
    return cell;
}

- (void)toggleChanged:(UISwitch *)sender {
    IrisSetAppearanceValue(sender.tag == 0 ? IrisHeaderEnabled : IrisHeaderSubtitleEnabled, @(sender.on), NULL);
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)path {
    [tableView deselectRowAtIndexPath:path animated:YES];
    if (path.section == 1) {
        if (path.row == 0) [self chooseAppearanceFile];
        else [self exportAppearanceFromView:(UIView *)[tableView cellForRowAtIndexPath:path] ?: tableView];
        return;
    }
    if (path.row < 2) return;
    NSArray *keys = @[IrisHeaderTitle, IrisHeaderSubtitle, IrisHeaderColorHex];
    NSArray *labels = @[@"Title", @"Subtitle", @"Text color"];
    [self editPreference:keys[path.row - 2] label:labels[path.row - 2]];
}

- (void)editPreference:(NSString *)key label:(NSString *)label {
    BOOL isColor = [key isEqualToString:IrisHeaderColorHex];
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
