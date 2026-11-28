#import "IrisMediaViewController.h"
#import <AVFoundation/AVFoundation.h>
#import <Photos/Photos.h>
#import <PhotosUI/PhotosUI.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

static NSString *const IrisAlbumNameKey = @"iris_custom_photo_album";
static NSString *const IrisCustomAlbumEnabledKey = @"iris_custom_photo_album_enabled";

typedef NS_ENUM(NSInteger, IrisMediaRow) {
    IrisMediaAlbum,
    IrisMediaSave,
    IrisMediaExportAudio,
    IrisMediaShare,
};

@interface IrisMediaViewController () <UIDocumentPickerDelegate, PHPickerViewControllerDelegate>
@property (nonatomic) IrisMediaRow pendingAction;
@property (nonatomic) BOOL busy;
@end

static NSString *IrisAlbumTitle(void) {
    NSUserDefaults *preferences = NSUserDefaults.standardUserDefaults;
    if (![preferences boolForKey:IrisCustomAlbumEnabledKey]) return @"";
    id title = [preferences objectForKey:IrisAlbumNameKey];
    return [title isKindOfClass:NSString.class] ? title : @"";
}

static NSURL *IrisTemporaryMediaDirectory(NSError **error) {
    NSURL *directory = [[NSURL fileURLWithPath:NSTemporaryDirectory() isDirectory:YES]
        URLByAppendingPathComponent:NSUUID.UUID.UUIDString isDirectory:YES];
    return [NSFileManager.defaultManager createDirectoryAtURL:directory withIntermediateDirectories:NO
                                                   attributes:nil error:error] ? directory : nil;
}

@implementation IrisMediaViewController

- (instancetype)init {
    return [super initWithStyle:UITableViewStyleInsetGrouped];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Media";
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    (void)tableView;
    (void)section;
    return 4;
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    (void)tableView;
    (void)section;
    return @"Save or extract audio from a file you choose, or share an item from Photos.";
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)path {
    (void)tableView;
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:nil];
    cell.textLabel.text = (@[@"Photos album", @"Save photo or video", @"Export audio as M4A", @"Share from Photos"])[path.row];
    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    if (path.row == IrisMediaAlbum) {
        NSString *title = IrisAlbumTitle();
        cell.detailTextLabel.text = title.length ? title : @"Library";
    }
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)path {
    [tableView deselectRowAtIndexPath:path animated:YES];
    if (self.busy) return;
    if (path.row == IrisMediaAlbum) {
        [self editAlbum];
        return;
    }
    if (path.row == IrisMediaShare) {
        PHPickerConfiguration *configuration = [PHPickerConfiguration new];
        configuration.filter = [PHPickerFilter anyFilterMatchingSubfilters:@[PHPickerFilter.imagesFilter, PHPickerFilter.videosFilter]];
        configuration.preferredAssetRepresentationMode = PHPickerConfigurationAssetRepresentationModeCurrent;
        PHPickerViewController *picker = [[PHPickerViewController alloc] initWithConfiguration:configuration];
        picker.delegate = self;
        [self presentViewController:picker animated:YES completion:nil];
        return;
    }
    self.pendingAction = path.row;
    NSArray<UTType *> *types = path.row == IrisMediaSave ? @[UTTypeImage, UTTypeMovie] : @[UTTypeAudio, UTTypeMovie];
    UIDocumentPickerViewController *picker = [[UIDocumentPickerViewController alloc] initForOpeningContentTypes:types asCopy:YES];
    picker.delegate = self;
    [self presentViewController:picker animated:YES completion:nil];
}

- (void)editAlbum {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Photos album"
        message:@"Leave the name blank to save to the main library." preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *field) { field.text = IrisAlbumTitle(); }];
    UITextField *field = alert.textFields.firstObject;
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    __weak typeof(self) weakSelf = self;
    [alert addAction:[UIAlertAction actionWithTitle:@"Save" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        (void)action;
        NSString *title = [(field.text ?: @"") stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        if (title.length > 80 || [title rangeOfCharacterFromSet:NSCharacterSet.newlineCharacterSet].location != NSNotFound) {
            dispatch_async(dispatch_get_main_queue(), ^{ [weakSelf showMessage:@"Enter a single line of up to 80 characters."]; });
            return;
        }
        NSUserDefaults *preferences = NSUserDefaults.standardUserDefaults;
        [preferences setObject:title ?: @"" forKey:IrisAlbumNameKey];
        [preferences setBool:title.length > 0 forKey:IrisCustomAlbumEnabledKey];
        [weakSelf.tableView reloadData];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)setProcessing:(BOOL)processing {
    self.busy = processing;
    self.navigationItem.hidesBackButton = processing;
    self.navigationController.modalInPresentation = processing;
    self.tableView.userInteractionEnabled = !processing;
    if (processing) {
        UIActivityIndicatorView *spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
        [spinner startAnimating];
        self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithCustomView:spinner];
    } else {
        self.navigationItem.rightBarButtonItem = nil;
    }
}

- (void)documentPicker:(UIDocumentPickerViewController *)picker didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
    (void)picker;
    NSURL *source = urls.firstObject;
    if (!source || self.busy) return;
    IrisMediaRow action = self.pendingAction;
    [self setProcessing:YES];
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSError *error = nil;
        NSURL *directory = IrisTemporaryMediaDirectory(&error);
        NSURL *file = [directory URLByAppendingPathComponent:source.lastPathComponent];
        BOOL scoped = [source startAccessingSecurityScopedResource];
        BOOL copied = file && [NSFileManager.defaultManager copyItemAtURL:source toURL:file error:&error];
        if (scoped) [source stopAccessingSecurityScopedResource];
        dispatch_async(dispatch_get_main_queue(), ^{
            if (!copied) {
                [self finishInDirectory:directory message:error.localizedDescription ?: @"Could not open the selected file."];
            } else if (action == IrisMediaSave) {
                [self saveFile:file inDirectory:directory];
            } else {
                [self exportAudio:file inDirectory:directory];
            }
        });
    });
}

- (void)saveFile:(NSURL *)file inDirectory:(NSURL *)directory {
    UTType *type = [UTType typeWithFilenameExtension:file.pathExtension];
    BOOL video = [type conformsToType:UTTypeMovie];
    if (!video && ![type conformsToType:UTTypeImage]) {
        [self finishInDirectory:directory message:@"Choose a photo or video file with a recognized extension."];
        return;
    }
    NSString *albumTitle = IrisAlbumTitle();
    BOOL useAlbum = albumTitle.length > 0;
    NSDictionary *info = NSBundle.mainBundle.infoDictionary;
    BOOL hasRead = [info[@"NSPhotoLibraryUsageDescription"] length] > 0;
    BOOL hasAdd = [info[@"NSPhotoLibraryAddUsageDescription"] length] > 0;
    if ((useAlbum && !hasRead) || (!useAlbum && !hasAdd && !hasRead)) {
        [self finishInDirectory:directory message:@"This app build has no Photos permission description for that destination."];
        return;
    }
    PHAccessLevel level = (useAlbum || !hasAdd) ? PHAccessLevelReadWrite : PHAccessLevelAddOnly;
    [PHPhotoLibrary requestAuthorizationForAccessLevel:level handler:^(PHAuthorizationStatus status) {
        BOOL authorized = status == PHAuthorizationStatusAuthorized || (!useAlbum && status == PHAuthorizationStatusLimited);
        if (!authorized) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [self finishInDirectory:directory message:useAlbum ? @"Allow full Photos access in Settings to save to a named album." :
                                                                      @"Allow this app to add photos in Settings."];
            });
            return;
        }
        PHAssetCollection *album = nil;
        if (useAlbum) {
            PHFetchOptions *options = [PHFetchOptions new];
            options.predicate = [NSPredicate predicateWithFormat:@"title == %@", albumTitle];
            album = [PHAssetCollection fetchAssetCollectionsWithType:PHAssetCollectionTypeAlbum
                subtype:PHAssetCollectionSubtypeAlbumRegular options:options].firstObject;
        }
        [PHPhotoLibrary.sharedPhotoLibrary performChanges:^{
            PHAssetCreationRequest *asset = [PHAssetCreationRequest creationRequestForAsset];
            [asset addResourceWithType:(video ? PHAssetResourceTypeVideo : PHAssetResourceTypePhoto) fileURL:file options:nil];
            if (useAlbum) {
                PHAssetCollectionChangeRequest *albumChange = album ? [PHAssetCollectionChangeRequest changeRequestForAssetCollection:album] :
                    [PHAssetCollectionChangeRequest creationRequestForAssetCollectionWithTitle:albumTitle];
                PHObjectPlaceholder *placeholder = asset.placeholderForCreatedAsset;
                if (placeholder) [albumChange addAssets:@[placeholder]];
            }
        } completionHandler:^(BOOL success, NSError *error) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [self finishInDirectory:directory message:success ? @"Saved to Photos." : error.localizedDescription ?: @"Photos could not save the file."];
            });
        }];
    }];
}

- (void)exportAudio:(NSURL *)file inDirectory:(NSURL *)directory {
    AVURLAsset *asset = [AVURLAsset URLAssetWithURL:file options:nil];
    AVAssetExportSession *exporter = [[AVAssetExportSession alloc] initWithAsset:asset presetName:AVAssetExportPresetAppleM4A];
    if (!exporter || ![exporter.supportedFileTypes containsObject:AVFileTypeAppleM4A]) {
        [self finishInDirectory:directory message:@"Choose a supported file that contains audio."];
        return;
    }
    NSURL *output = [directory URLByAppendingPathComponent:@"Iris-Audio.m4a"];
    if ([output.lastPathComponent caseInsensitiveCompare:file.lastPathComponent] == NSOrderedSame) {
        output = [directory URLByAppendingPathComponent:@"Iris-Exported-Audio.m4a"];
    }
    exporter.outputURL = output;
    exporter.outputFileType = AVFileTypeAppleM4A;
    [exporter exportAsynchronouslyWithCompletionHandler:^{
        dispatch_async(dispatch_get_main_queue(), ^{
            if (exporter.status != AVAssetExportSessionStatusCompleted) {
                [self finishInDirectory:directory message:exporter.error.localizedDescription ?: @"Could not export the audio."];
                return;
            }
            [self shareFile:output inDirectory:directory];
        });
    }];
}

- (void)picker:(PHPickerViewController *)picker didFinishPicking:(NSArray<PHPickerResult *> *)results {
    NSItemProvider *provider = results.firstObject.itemProvider;
    if (provider) [self setProcessing:YES];
    [picker dismissViewControllerAnimated:YES completion:^{
        if (!provider) return;
        NSString *identifier = nil;
        for (NSString *candidate in provider.registeredTypeIdentifiers) {
            UTType *type = [UTType typeWithIdentifier:candidate];
            if ([type conformsToType:UTTypeImage] || [type conformsToType:UTTypeMovie]) {
                identifier = candidate;
                break;
            }
        }
        if (!identifier) {
            [self finishInDirectory:nil message:@"Choose a photo or video."];
            return;
        }
        [provider loadFileRepresentationForTypeIdentifier:identifier completionHandler:^(NSURL *source, NSError *failure) {
            NSError *error = failure;
            NSURL *directory = source ? IrisTemporaryMediaDirectory(&error) : nil;
            NSURL *target = [directory URLByAppendingPathComponent:source.lastPathComponent];
            BOOL copied = target && [NSFileManager.defaultManager copyItemAtURL:source toURL:target error:&error];
            dispatch_async(dispatch_get_main_queue(), ^{
                if (copied) [self shareFile:target inDirectory:directory];
                else [self finishInDirectory:directory message:error.localizedDescription ?: @"Could not open the selected item."];
            });
        }];
    }];
}

- (void)shareFile:(NSURL *)file inDirectory:(NSURL *)directory {
    UIActivityViewController *activity = [[UIActivityViewController alloc] initWithActivityItems:@[file] applicationActivities:nil];
    activity.popoverPresentationController.sourceView = self.tableView;
    CGRect bounds = self.tableView.bounds;
    activity.popoverPresentationController.sourceRect = CGRectMake(CGRectGetMidX(bounds), CGRectGetMidY(bounds), 1, 1);
    activity.completionWithItemsHandler = ^(UIActivityType type, BOOL completed, NSArray *items, NSError *error) {
        (void)type; (void)completed; (void)items; (void)error;
        [NSFileManager.defaultManager removeItemAtURL:directory error:NULL];
    };
    [self setProcessing:NO];
    [self presentViewController:activity animated:YES completion:nil];
}

- (void)finishInDirectory:(NSURL *)directory message:(NSString *)message {
    if (directory) [NSFileManager.defaultManager removeItemAtURL:directory error:NULL];
    [self setProcessing:NO];
    [self showMessage:message];
}

- (void)showMessage:(NSString *)message {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Iris Media" message:message preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

@end
