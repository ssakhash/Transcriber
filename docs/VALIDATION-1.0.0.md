# Personal release validation

Status: implemented and packaged for personal use. The checks below passed, but the full production acceptance gate remains open. Do not describe this release as fully production-validated.

## Release identity

- Version: 1.0.0, build 1, arm64, macOS 26 minimum.
- Implementation SHA-256: `1ffe0d8b5505ad50311f52d1904dc773bffdd17fedb0f0bd731d79fd7405d47c`.
- Release ZIP SHA-256: `cad30f7da749607ae0704cb64d2ba7833e8f5abf483e07ae364be169e0ce6b6d`.
- Validation dates: September 20 and 21, 2026.
- Host: Apple silicon Mac16,1, macOS 26.6.2, Xcode 27.0, Swift 6.4.
- Signing: ad-hoc, with App Sandbox and hardened runtime. Developer ID signing, notarization, and public distribution are not claimed.
- This initial workspace has no committed revision. The implementation digest identifies the exact source snapshot; `build/Release/SHA256SUMS` identifies the ZIP. Before public release, commit and tag the reviewed source as described in [RELEASING.md](RELEASING.md).

`Scripts/source-digest.py` includes the app, package, configuration, project, tests, tools, build scripts, and CI configuration. It excludes private signing settings, build output, and documentation. The clean source export and working source have matching digests. Any implementation change invalidates this record until relevant checks are repeated.

## Completed checks

| Area | Evidence and result | Limits |
| --- | --- | --- |
| Clean build | Tests and Release app built from a fresh source export with no inherited build directory. 13 Swift tests passed, including the two cases of the incompatible-session test. | A source export was used because there is no committed revision. Hosted CI has not run. |
| Transcript correctness | Tests cover chronological final assembly, replay prevention, invalid times, stale callbacks, normalized edits, preserved original timing, safe splitting, speaker rename propagation, export consistency, incomplete output, and dirty tracking. | Recognition accuracy requires separate human review. |
| Name suggestions | Explicit self-introduction produces an evidence-linked suggestion; negative cases and duplicate evidence are rejected. Creating and renaming a speaker from a suggestion worked in the app. | Names are suggestions, not voice identification. |
| Media decoding | Stereo AAC in MP4, 48 kHz to 16 kHz mono conversion, a two-second delayed start, two audio tracks, five seconds of silence, missing audio, and corrupt media exercised. The delayed fixture yielded exactly 352,000 output frames over 22 seconds, with first audible content at 2.0203125 seconds. | Other codec profiles, edit-list variants, and damaged-file patterns remain unverified. |
| Speech finalization | Generated English speech yielded both expected opening and final phrases. Silent input produced no transcript. Audio reached its expected ending time. | The installed English model was used. |
| Track selection | Selected Audio 2 in the app and completed recognition. Playback uses a composition containing only the selected audio track when several exist. | The generated tracks carry the same speech; a distinct-content track fixture is still desirable. |
| Three-hour processing | Completed a 10,800-second generated MP4 in the probe and the app. Both produced 1,443 passages and 8,664 words, beginning at 0 and ending at 10,799.58 seconds. Opening and closing fixture phrases verified. | Repeated synthesized speech separated by silence, not three hours of continuous natural conversation. |
| Memory and responsiveness | Probe elapsed time: 46.48 seconds; maximum resident memory: 31.27 MiB. Highest sampled app resident memory: 164.06 MiB during the latter part of the run. Transcript scrolling remained usable while processing. Audio is pulled in bounded buffers. | Measurements exclude Apple's separate speech service. App sampling is not a complete peak measurement; no formal interaction latency benchmark was run. |
| Real recording | The user-supplied 605.56-second recording completed locally in 8.97 seconds, producing 80 passages and 1,181 words through 604.32 seconds. Probe maximum resident memory: 28.92 MiB. | No word-error score or listening review. The source was no longer at its original location during the follow-up session. Private output stays in ignored build storage. |
| Cancellation and restart | Cancelled after receiving completed passages, verified retained passages and no callbacks after cancellation completed, then immediately transcribed another fixture using the same service. Repeated with the clean-build probe. | Cancellation at every installation/preparation/finalization boundary has not been exercised. |
| Session recovery | Unit tests restore an in-progress session as interrupted. The app restored all 1,443 passages after quit and relaunch using an isolated validation bundle identifier. | Forced termination, power loss, and actual sleep/wake remain unverified. |
| Storage failure | Read-only directory test preserved the previous JSON. A dedicated disposable 16 MiB volume was filled; a failed save preserved the original session, and a retry succeeded after freeing space. The volume was detached. | No system volume was filled. |
| Incompatible data | Corrupt, unsupported-version, and structurally invalid saved sessions are protected. Explicit preservation creates a unique backup before a fresh session can be saved. | UI recovery for every malformed input shape is not exhaustive. |
| Editing and export | Exercised corrections, speaker assignment and renaming, recognized-word splitting, timestamp seeking, timestamp toggle, clipboard output, default filename, Save As cancellation, successful UTF-8 save, and replacement warning. Entered disallowed punctuation was normalized. | Native overwrite confirmation and expired bookmarks still require explicit acceptance checks. |
| Interface | Reviewed the dark studio layout, native playback, accessible control labels, command shortcuts, and large transcript scrolling. The release app rendered the documented preview successfully. | Full VoiceOver listening, minimum-size review, focus traversal, and measured contrast audit remain open. |
| Content | Automated scan passed on owned text, compiled app strings, metadata, generated fixture output, and the private real-recording export. | Apple's own system dialogs and source media are outside app-owned content. |
| Packaging | Clean Release build, strict signature verification, ZIP extraction verification, and SHA-256 verification completed. App icon and arm64 executable included. | Clean macOS user first launch, upgrades, Developer ID, notarization, and Gatekeeper distribution checks remain open. |

During UI validation, the SwiftUI video wrapper failed at runtime with this toolchain. The app now embeds AppKit's `AVPlayerView` directly. Import, playback controls, transcription, and restoration were exercised after that change.

## Reproduce the automated checks

Run from the repository root in a logged-in macOS session:

```sh
bash Scripts/test.sh
bash Scripts/check-media.sh --speech
bash Scripts/check-storage.sh
bash Scripts/build.sh
python3 Scripts/source-digest.py
(cd build/Release && shasum -a 256 -c SHA256SUMS)
```

The storage script creates and fills only a small disposable disk image under `build`. The probe refuses a volume with the wrong name or a capacity of 64 MiB or more. Build and validation tools use normal macOS media and speech services.

To repeat the endurance and cancellation checks:

```sh
mkdir -p build/endurance
say -v Samantha -r 155 -o build/endurance/speech.aiff 'Hello, my name is John Smith. Today we are testing local video transcription. Every word stays on this Mac. The final sentence is complete.'
build/swift-package/debug/MediaProbe generate build/endurance/three-hours.mp4 build/endurance/speech.aiff 10800
/usr/bin/time -l build/swift-package/debug/MediaProbe transcribe build/endurance/three-hours.mp4 build/endurance/transcript.txt --session
build/swift-package/debug/MediaProbe generate build/endurance/short.mp4 build/endurance/speech.aiff 22
build/swift-package/debug/MediaProbe cancel-restart build/endurance/three-hours.mp4 build/endurance/short.mp4
python3 Scripts/check-content.py build/endurance/transcript.txt
```

Inspect the resulting passage JSON for beginning and ending timing, verify both fixture phrases, and record memory for the app and speech service separately when evaluating total system usage. Probe timings are observations on this host, not performance promises.

Local evidence is in ignored build files: `clean-tests.log`, `clean-build.log`, `media-tests.log`, `endurance.log`, `gui-endurance.json`, `real-video.log`, `cancel-restart.log`, `storage-tests.log`, and `final-snapshot.log`. Private recordings and transcript contents must not be committed or included in release materials.

## Remaining production acceptance work

1. Review natural single-speaker and conversation recordings by listening, correcting a reference transcript, and checking playback alignment. Include a representative long, continuous recording and additional MP4 audio profiles.
2. Exercise first model installation, interruption and recovery of that installation, and offline behavior with and without installed assets. Do not remove a user's existing models to perform this test.
3. Exercise cancellation at each stage, forced quit, real sleep/wake, missing source files, expired security-scoped access, and recovery after processing failure.
4. Complete native overwrite handling, UI autosave-failure recovery, relinking, keyboard focus traversal, window resizing, VoiceOver, and contrast review.
5. Test the extracted release in a clean macOS user account and perform upgrade checks with saved sessions. Complete signing and notarization checks only when public distribution is requested.

Record the tester, date, source digest or commit, package checksum, expected result, actual result, and evidence for each remaining check. Keep this release marked as partially validated until those required checks pass.
