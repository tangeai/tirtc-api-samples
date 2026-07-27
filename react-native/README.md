# TiRTC React Native API Sample

This sample consumes `tirtc-react-native@2.2.0` from the public npm
registry. Android and iOS native TiRTC dependencies are resolved by that
published package.

## Install

```bash
npm ci
```

## Run

```bash
npm run android
npm run ios
```

For iOS, run `cd ios && pod install` before opening
`ios/TiRtcExample.xcworkspace`. Configure your own Apple development team when
running on a device. `Podfile.lock` is generated locally and intentionally
ignored; the release gate records the resolved lock separately and verifies the
exact TiRTC CocoaPods versions. See the
[TiRTC documentation](https://docs.tange.ai/products/tirtc/) for credentials and
API guidance.
