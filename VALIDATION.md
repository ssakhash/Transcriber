# Personal release validation

Status: version 1.1.0 implements the native Liquid Glass workspace and is packaged for personal use. The checks below passed. The complete production acceptance gate remains open, so this release is not described as fully production-validated.

## Release identity

- Version: 1.1.0, build 2, arm64, macOS 26 minimum.
- Implementation SHA-256: `62f00e0b0d1f5d5b7bc7f22517aa2061b10b5f241ff77f9901ff3b0c908d784b`.
- Release ZIP SHA-256: `27c7933b17f56f1bded8082e5f2f6786b43b46ba9e1344d4bae6298c24493997`.
- Final build and editor verification: September 23, 2026.
- Host: Apple silicon Mac16,1, macOS 26.6.2, Xcode 27.0, Swift 6.4.
- Signing: ad-hoc, App Sandbox and hardened runtime enabled. Developer ID signing and notarization remain separate distribution work.
- No committed revision exists in this workspace. The implementation fingerprint identifies the exact source snapshot. Commit and tag reviewed source before distribution, following [RELEASING.md](docs/RELEASING.md).

`Scripts/source-digest.py` includes application code, package code, configuration, project, tests, tools, scripts, and CI configuration. It excludes private signing settings, build artifacts, and documentation. The final clean source export and working source have matching fingerprints. Any implementation change requires relevant validation to be repeated.

## Verified for the redesign

| Area | Result and evidence | Limits |
| --- | --- | --- |
| Clean build | A fresh source export with no inherited build directory passed 13 Swift tests and built the Release app using the macOS 27 SDK with a macOS 26 deployment target. | Local export, not a committed checkout or hosted CI run. |
| Core correctness | Existing tests pass for final assembly, replay prevention, invalid times, stale jobs, normalized edits, original timing, splitting, speaker rename propagation, names, export, dirty tracking, interrupted restoration, protected sessions, and failed writes. | The test count includes a parameterized incompatible-session test. Speech accuracy is not established by these tests. |
| Native structure | Native titled window, unified toolbar, NavigationSplitView, resizable sidebar, plain transcript, standard glass buttons, semantic colors, and safeAreaBar status inspected. No app-owned dark panel fills or forced appearance remain. | A visual redesign does not establish all production gates. |
| Appearance | Reviewed Light and Dark Mode, active and inactive windows, Increase Contrast, Reduce Transparency, and Reduce Motion. Original system preferences were restored. Actual window screenshots include the toolbar and sidebar. | No quantitative contrast measurement or complete assistive-technology audit. |
| Layout | Exercised sidebar collapse and resize, 940 by 650 minimum content size, toolbar fit, long source names, and long speaker names. Toolbar actions remain available with the sidebar hidden. | Not every localized system-label length or display scale was exercised. |
| Passage editor | Focused text reflows when detail width changes. Multiline text, trailing blank lines, selection, typing, Tab traversal, punctuation normalization, undo, and redo verified. The final NSTextView bridge fixes stale wrapping from a focused SwiftUI field. Normalization occurs before undo records the replacement range. | Continuous pointer dragging was verified on the earlier redesign; the final bridge was checked through sidebar collapse and expansion after the UI driver's coordinate-drag API became unavailable. |
| Import and speech | Imported generated MP4, selected Audio 2, and completed on-device recognition of eight passages and 48 words. Native playback controls remained available. | Both generated audio tracks contain the same speech. Model assets were already installed. |
| Editing and speakers | Corrected passages, added and renamed speakers, verified assigned names update, split at a recognized word, and sought playback using timestamps. The playing-passage accessibility state was verified. | Manual speaker labeling only; no voice separation is claimed. |
| Export | Exercised Copy All, timestamp option, Save As, expected filename, and UTF-8 output. Inspected normalized text, speaker labels, and split-passage timestamps in the generated fixture export. Complete and Exported are separate states. | Native overwrite and all save-panel failure paths still need explicit acceptance checks. |
| Recovery and large transcripts | Quit during a three-hour fixture, saved 1,020 passages and 6,126 words through 7,651.92 seconds, and restored all completed passages as Incomplete. Scrolled to the last restored passage. Command-Period canceled preparation and another short transcription then completed. | This was an interruption test, not a completed three-hour endurance run on 1.1.0. No formal UI latency or new memory benchmark was recorded. |
| Accessibility | Inspected individual native accessibility roles and descriptive labels for fields, passage editors, seek buttons, menus, toolbar actions, and progress. Checked keyboard movement and visible text selection/caret. | Full VoiceOver listening and complete keyboard-only coverage remain open. |
| Content | Automated checks passed for owned source and documentation, compiled app strings and metadata, and the generated fixture export. | System-owned dialogs and unchanged source media are outside the app-owned content policy. |
| Packaging | Clean Release build, strict signature verification, ZIP checksum, extraction, extracted signature, and executable equality verified. Bundle version, arm64 architecture, sandbox entitlements, hardened runtime, and minimum OS verified. | Clean-user launch, upgrade acceptance, Developer ID, notarization, and Gatekeeper distribution remain open. |

UI validation used `com.akhash.Transcriber.GlassValidation` and generated fixtures, separate from the normal application container. The synthetic `--preview` mode bypasses session reads and writes. The current user transcript was not replaced for these checks.

The existing AppModel and TranscriberKit processing, export, and persistence APIs were preserved. Session format is unchanged. The [1.0.0 validation record](docs/VALIDATION-1.0.0.md) retains the prior media matrix, full three-hour run, memory observations, real-recording probe, cancellation, and disposable full-volume tests. Those results belong to their recorded source fingerprint and are not represented as reruns on 1.1.0.

## Screenshots

- [Dark Mode, actual window](docs/studio.png)
- [Light Mode, actual window](docs/studio-light.png)

Screenshots use synthetic preview text. Playback and transcription are disabled because this preview has no source file. No private recording or transcript is included.

## Reproduce

```sh
bash Scripts/test.sh
python3 Scripts/check-content.py
bash Scripts/build.sh
python3 Scripts/source-digest.py
(cd build/Release && shasum -a 256 -c SHA256SUMS)
```

For media and storage acceptance, use `bash Scripts/check-media.sh --speech` and `bash Scripts/check-storage.sh` in a logged-in macOS session. The storage script fills only a dedicated disposable test image. The archived 1.0.0 record includes the endurance commands and measurement caveats.

Local evidence is in ignored build storage: `glass-final-tests.log`, `glass-final-build.log`, `glass-validation-build.log`, `glass-interruption.json`, and `fixtures/glass-validation-transcription.txt`. `clean-glass-final` contains the fresh source export and its clean build. `glass-final-extracted` contains the verified extracted app. Private recordings and transcripts must not enter source control or release materials.

## Remaining production acceptance work

1. Listen to representative natural single-speaker and conversation recordings, check timing, and compare against a corrected reference. Complete a representative three-hour run on this revision with beginning and ending checks and memory measurements, including the speech service.
2. Exercise first model installation, interruption and recovery, and offline behavior with and without installed assets. Do not remove a user's installed models to test this.
3. Exercise cancellation at every stage, forced termination, sleep/wake, missing files, expired bookmarks, relinking, and processing failure recovery on this revision.
4. Exercise the redesigned autosave-error presentation and Retry, save cancellation and native overwrite paths, plus clean-user first launch and upgrades with existing sessions.
5. Complete a VoiceOver listening review, exhaustive keyboard-only navigation, and measured contrast review. Repeat resize and large-transcript checks across representative displays.
6. Complete Developer ID, notarization, Gatekeeper, and public-distribution checks only for a separately authorized distribution release.

For each remaining check, record the tester, date, source fingerprint or commit, ZIP checksum, expected result, actual result, and evidence. Keep this release marked as partially validated until the required checks pass.
