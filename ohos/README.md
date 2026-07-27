# TiRTC OHOS API Sample

This project demonstrates the TiRTC OHOS client playback flow and microphone
talkback with the published `tirtc@2.2.6` package.

## Requirements

- DevEco Studio with an OpenHarmony / HarmonyOS NEXT SDK compatible with API 23
- OHPM

## Run

1. Open this `ohos/` directory in DevEco Studio.
2. Run `ohpm install`.
3. For a physical device, open `Project Structure → SigningConfigs` and enable
   the DevEco Studio automatic signing workflow recommended by the platform.
4. Select the `entry` module and run the application.

Generated certificates, profiles and signing configuration are local developer
state and must not be committed.

The project intentionally consumes the exact public dependency in both package
manifests:

```json5
{
  "dependencies": {
    "tirtc": "2.2.6"
  }
}
```

TiRTC documentation: https://docs.tange.ai/products/tirtc/
