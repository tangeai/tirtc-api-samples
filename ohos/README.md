# TiRTC OHOS 2.6.0-alpha.18

Run `python3 download_sdk.py` to download and verify the exact GitHub HAR, then run `ohpm install` and the normal unsigned HAP build.
Both dependency files use relative file dependencies; they do not fetch the HAR themselves.
sdk.json records the immutable version, URL, size and SHA-256. Restricted networks can mirror the exact bytes internally while preserving size and SHA-256.
