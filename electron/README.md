# TiRTC Electron API Sample

This is the canonical RTC and Ti Cloud Storage desktop Sample for exactly
`tirtc-electron@2.4.0`. The checked-in lockfile is the install
contract: use `npm ci`, then `npm run build` and `npm start`.

## Credentials

Tokens stay in the Electron Main process and never enter DOM state, renderer IPC
arguments, logs, or persisted settings. Provide one credential source before launch:

- RTC: `TIRTC_EXAMPLE_RTC_TOKEN` or a one-shot UTF-8 file descriptor in
  `TIRTC_EXAMPLE_RTC_TOKEN_FD`; the configured DevTools token server is fetched by Main.
- Ti Cloud Storage: `TIRTC_EXAMPLE_TI_CLOUD_STORAGE_TOKEN` or
  `TIRTC_EXAMPLE_TI_CLOUD_STORAGE_TOKEN_FD`.

Prefer the file-descriptor form for automation. Main deletes the corresponding
environment entry after reading it. Never expose production credentials in a public
Sample checkout.

## RTC path

1. Enter endpoint, app ID, remote device ID, and distinct audio/video stream IDs.
2. Start the session, subscribe to media, send a command, and inspect metrics.
3. Optionally record or take a snapshot. The Sample copies a returned SDK file into the
   user's Downloads directory, then calls the public file `delete()` method. A failed
   temporary-file deletion can be retried without creating another Downloads copy.
4. Leave the session before closing the application. Outputs detach and dispose before
   the connection and `TiRtc.shutdown()`.

## Ti Cloud Storage path

1. Enter endpoint, app ID, and audio/video channel IDs, then list recording days and ranges.
2. Create a replay, attach audio/video outputs, play, pause, seek, change speed, record, or
   export a bounded range.
3. Saved recording, export, and snapshot files use the same copy-then-delete ownership as RTC.
4. Stop replay, detach/dispose outputs, dispose replay and storage, then call
   `TiCloudStorage.shutdown()`.

The Sample requests only the macOS microphone permission used by local audio input; it
does not request camera access. Production macOS distribution still requires your own
signing identity, hardened-runtime/entitlement review, and notarization policy.

Package an unsigned development directory with `npm run package:dir`. Electron Builder
keeps ASAR enabled, unpacks only the selected native tuple, and is not a substitute for
your release signing and installer validation.
