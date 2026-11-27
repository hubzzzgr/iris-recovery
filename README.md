# Iris source recovery

Owner-maintained ARM64 iOS build reconstructed from the original Iris dylib. This build initializes the recovered header feature directly. It has no Iris account, product-key, or backend dependency.

## Recovered behavior

- Header appearance uses the original `SIGHeader` target and layout, window attachment, trait, and item-transition callbacks. Each callback calls the host implementation before updating the Iris accessory. The gear opens a local settings sheet.
- Header title, subtitle, and text color use the recovered Iris preference keys with host-local preferences.
- Settings export and import use a versioned, local JSON appearance file. This new format supports the reconstructed preferences. The legacy transfer envelope and other preference domains remain unrecovered.

| Recovered evidence | Source |
| --- | --- |
| Header registration at `0x34b578`, layout replacement at `0x34b2cc`, and overlay at `0x3c1ee4` | `Sources/IrisHeader.m` |
| Header preference strings at `0x543e10`, `0x543e30`, `0x5444f0`, `0x544510`, and `0x5447b0` | `Sources/IrisPreferences.m` |
| Settings controller at `0x35d160` and local settings transfer at `0x34ffa4` and `0x3533b8` | `Sources/IrisSettingsViewController.m` |

Feature parity is incomplete. Media tools, messaging features, and the pull-to-refresh visuals are outside this recovered build. Compatibility with individual host versions and operation on a device still need validation.

## Build

Run `bash scripts/build-ios.sh` on macOS with Xcode and the iPhoneOS SDK. This creates `build/iris.dylib` and `build/SHA256SUMS`. The script checks the Mach-O file type, architecture, and install name. GitHub Actions runs the same script and publishes those two files as the `iris-ios-arm64` artifact.
