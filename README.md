# Iris offline rebuild

This standalone ARM64 dylib targets iOS 15.0 and later. It opens Iris settings from the header gear and stores them on the device. Iris settings require no account, product key, or backend.

## Recovered behavior

- The header accessory uses `SIGHeader` layout, window attachment, trait and item-transition callbacks. Its gear has priority in hit testing. Other touches fall through to the host.
- The title, subtitle and switches support independent colors. Settings from the earlier JSON rebuild still import, and the subtitle inherits the title color until it has its own color setting.
- Pull to Refresh offers a spinner tint, five rainbow palettes and a custom three-color palette. The settings page includes a UIKit preview. The effect applies to standard `UIRefreshControl` views. Animation follows the system Reduce Motion setting.
- Media saves a photo or video you select in Files to the main Photos library or a named album. It can extract M4A audio from a selected audio or video file and open the iOS share sheet. **Share from Photos** opens the system photo picker for one item at a time. Named albums require the host to declare Photos access and permission to be granted in iOS.
- **App permissions in Settings** opens the host app’s iOS settings, where you can change location and Photos permissions.
- Transfer supports versioned JSON files and QR codes. **Show settings QR** displays a shareable image. **Import QR from Photos** reads a QR image you select. QR import applies the supported appearance settings and resets omitted appearance fields to their defaults. JSON import updates the fields present in the file.
- The Iris app icon option appears when the host bundle supplies the original `icon_iris2` alternate icon and iOS reports support.

| Recovered evidence | Source |
| --- | --- |
| Header registration at `0x34b578`, touch handling at `0x34ad24`, and overlay at `0x3c1ee4` | `Sources/IrisHeader.m` |
| Appearance preference strings and the `IRS1` Zstandard envelope at `0x34ffa4` and `0x3533b8` | `Sources/IrisPreferences.m` |
| QR rendering at `0x34ffa4` and alternate icon API call at `0x3a2228` | `Sources/IrisSettingsViewController.m` |
| Refresh theme and rainbow rendering at `0x3d3804`, `0x3d5854` and `0x3d77a4` | `Sources/IrisRefresh.m` |
| Photos asset and album requests at `0x325f48` and `0x3268b8`, and M4A export at `0x41a670` | `Sources/IrisMediaViewController.m` |

Feature parity is incomplete. The refresh visuals use UIKit and Core Animation. Support for Snapchat’s custom ghost animation remains unverified. The media tools operate on explicitly selected items. Automatic media capture, chat features, and original location features remain absent. Operation in Snapchat still needs device testing against a compatible host version.

QR and JSON transfers include the header and refresh preferences. The original app resets all of its settings on QR import, so a QR exported by this rebuild can reset other settings if imported into the original.

## Build

Run `bash scripts/build-ios.sh` on macOS with Xcode and the iPhoneOS SDK. The script fetches and verifies the pinned Zstandard source if needed. Set `IRIS_ZSTD_DIR` to use an existing extraction of Zstandard 1.5.7.

On Windows, run `scripts/build-ios.ps1` with `-ToolchainBin`, `-Sdk`, and `-Zstd` pointing to the Windows ARM64 iOS Clang/LLD `bin` directory, the iPhoneOS SDK root, and the extracted Zstandard source root respectively. The Windows build was developed with the pinned LLVM 19 toolchain and the iPhoneOS 16.5 SDK from [TheosWin releases](https://github.com/CacheW/TheosWin/releases).

Both scripts produce `build/iris.dylib`, `build/SHA256SUMS` and `build/Zstandard-LICENSE.txt`. GitHub Actions uses the macOS script and uploads the same files as `iris-ios-arm64`. The Windows artifact is unsigned.
