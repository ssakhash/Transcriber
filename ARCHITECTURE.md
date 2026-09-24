# Architecture

## Boundaries

The Xcode application owns the SwiftUI interface, AppKit file panels, AVPlayer, security-scoped bookmarks, and application lifecycle. `AppModel` is main-actor isolated and observable. The `TranscriberKit` Swift package contains independently testable transcript, persistence, media, and speech services.

The app uses public macOS 26 APIs and Swift 6 concurrency checking. The application target defaults to main-actor isolation; processing in the package uses explicit actors. There are no external packages.

## Native workspace

`TranscriberApp` owns the model, standard titled window, unified toolbar configuration, commands, and lifecycle. `TranscriberRootView` arranges a `NavigationSplitView`, toolbar actions, drag-and-drop, and passage splitting. Sidebar visibility is local presentation state, independent of session storage.

`TranscriberSidebar` contains scrollable tool sections. It deliberately avoids a selectable source list because this panel contains editable fields, pickers, and multiple actions. Controls retain individual accessibility roles. `TranscriptDetailView` owns a lazy, plain-text passage editor and a `safeAreaBar` for status and recoverable errors. Passage rows, speaker controls, the split sheet, status messages, and the native video wrapper are separate components.

The system supplies navigation materials, toolbar grouping, glass button styles, scroll-edge effects, appearance, and accent color. No app-owned panel fills, custom blur layers, or forced color scheme are applied. An accent marker identifies the current passage without tinting its text surface. `AVPlayerView` remains an AppKit bridge and owns playback controls.

Editable passages use a small `NSTextView` bridge inside SwiftUI. Native text layout measures each visible passage at its proposed width, including while focused, so resizing the window or sidebar cannot leave a stale single-line field editor. The editor uses semantic fonts and colors, has no painted background, and retains native text selection, spelling, and undo behavior. Punctuation normalization happens before AppKit records replacement ranges so undo and redo preserve exact text. Tab and Shift-Tab move through controls.

The `--preview` launch argument uses synthetic content and bypasses session reads and writes. Capture screenshots from the running window so native materials and toolbar effects are composited correctly. Offscreen bitmap rendering is not representative of these effects. Normal launches always restore the existing session. Appearance is inherited from macOS in both modes.

## Audio and transcription

`MediaInfo` loads asset metadata asynchronously and enumerates audio tracks. `AudioReader` confines AVAssetReader, audio buffers, and AVAudioConverter to one actor. A pull-based asynchronous sequence supplies the next converted buffer only when the analyzer requests it. There is no unbounded audio queue or dropped-buffer policy. Buffers are owned independently after conversion.

Output timestamps use an integer frame clock anchored to source presentation time. Source gaps and format changes flush the previous converter before a new clock anchor is installed. End of input drains the converter. Backward discontinuities fail explicitly. AVFoundation expands MP4 edit-list silence where appropriate.

`TranscriptionService` checks hardware and English locale support, retains an English asset reservation, installs missing assets through macOS, and negotiates the analyzer format. It consumes final results concurrently with audio input. Either branch failing cancels the reader and analyzer. Parent cancellation performs the same cleanup. Only one call can use a service at a time.

Progress measures audio decoded, capped below completion while recognition finalizes. It is not an estimate of remaining wall-clock time. Media buffers remain bounded; transcript text and timings necessarily grow with recognized words. Apple's speech model runs in a system service, so app memory measurements exclude that service.

## Transcript and editing

`TranscriptSession` stores source metadata, a selected track, an optional bookmark, state, speakers, passages, export preferences, and revision counters. A passage contains original normalized text, edited text, a time interval, timed text runs, and an optional speaker ID. Speakers are separate entities so renames update all assigned passages.

Only chronological final passages are accepted. `JobGate` prevents callbacks from a previous job from changing a new session. Editing changes text without inventing new timings. Splitting requires unchanged text, complete timing coverage, and an interior recognized boundary. Users can restore original text before splitting.

Name suggestions combine explicit self-introduction patterns with Natural Language personal-name tags. Candidates retain their source passage and time. Applying a suggestion is a user action that renames or creates a speaker and assigns the evidence passage. No identity is inferred from a face, voice, or incidental mention.

## Persistence and lifecycle

`SessionStore` serializes atomic JSON writes on an actor. A coalesced half-second save deadline prevents rapid results from postponing saving indefinitely. Shutdown cancels processing, waits for cleanup, and flushes the latest session. A failed flush offers a chance to stay and export.

Sessions saved while processing restore as interrupted. Restart begins at the beginning; resumable speech inference is not claimed. Corrupt, unsupported, or structurally invalid sessions block writes until the user preserves the file under a unique backup name. Original media remains outside the session store and is never modified.

Bookmarks are refreshed when stale. File size, modification date, and duration are checked on restore. Relinking requires matching duration, size, and track ID; these are practical checks, not cryptographic proof of media identity.

## Release controls

Content policy checks cover owned source and documentation, bundled text, and supplied output fixtures. Build scripts create fresh packaging directories and verify the app signature before making a ZIP. `SOURCE-SHA256` fingerprints implementation inputs independently of the validation document. Private media, build output, and signing settings stay outside version control.

Diagnostics record states and measurements, not user transcript text. Fixture probes write text only to an explicitly supplied output path. The app uses no camera, microphone, network, or broad filesystem entitlements.

The interface follows Apple's [Liquid Glass adoption guidance](https://developer.apple.com/documentation/TechnologyOverviews/adopting-liquid-glass), using standard navigation and controls while preserving a plain reading surface.
