# TiRTC iOS / macOS API Samples

This directory contains the shared TiRTC Apple-platform sample project. It keeps
the `ExampleIOS` and `ExampleMacOS` application targets and consumes the public
`TiRTC` CocoaPod at the exact version `2.2.9`.

## Run

```bash
pod install
open Example.xcworkspace
```

Choose `ExampleIOS` or `ExampleMacOS` in Xcode. Configure your own signing team
when running on an iOS device. See the
[TiRTC documentation](https://docs.tange.ai/products/tirtc/) for credentials and
API guidance.

The application targets use Swift 5 language mode with the current Swift
compiler. This is required for a clean consumer of the published `TiRTC
2.2.9` binary module, whose delegate object types do not yet expose Swift 6
`Sendable` annotations. The sample application source itself is unchanged.
