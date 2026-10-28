# XiaoLiao implementation plan

## Initial inspection — 2026-10-26

The repository began as an unchanged Xcode SwiftUI starter: `XiaoLiaoApp` launches a `ContentView` containing a globe and “Hello, world!”. It has an empty AccentColor, an empty AppIcon, and template XCTest/UI-test targets. There were no existing feature models, design tokens, package dependencies, backend code, or project instruction files. The starter used filesystem-synchronized target folders, Swift language mode 5, main-actor default isolation for the app, and iOS 26.5 deployment settings. A navigator workaround now uses explicit file references; retain the original build settings.

Figma is accessible. The supplied link targets the `mockup` canvas; individual frames provide the usable design context. See `AGENTS.md` for frame links and conventions.

## Milestone 1 — local conversation UI

Scope: New Conversation, a basic Conversation Feed, navigation, Figma mock messages, and selection-driven contextual actions. Stop here after implementation and handoff.

- [x] Inspect the starter and the relevant Figma frames.
- [x] Record architecture, conventions, references, and constraints in `AGENTS.md`.
- [x] Bundle original Figma artwork and centralize design colors.
- [x] Add deterministic message fixtures and a small observable conversation view model.
- [x] Implement the empty/filled topic input, local prompt suggestion, and chat button.
- [x] Navigate into the feed and return using the existing history control (explicit user preference).
- [x] Show the five-second partner audio bubble and “Yes, I also love turtles!” learner bubble.
- [x] Show only the selected message's adjacent actions; tapping it again or the background dismisses them (source implementation; runtime check pending).
- [x] Support local transcript/translation toggles and the existing text input/edit pattern. Keep audio-related actions unavailable; add no live AI behavior.
- [x] Add focused behavior/navigation tests and perform the checks available in this environment.
- [ ] Build and run tests in Xcode; compare simulator rendering with Figma.

Acceptance: the target should remain buildable; users can enter or seed a topic, open the mock feed, select either message, reveal the appropriate action rail, and return to the topic screen. Any source-only checks must be reported separately from a successful build.

### Implementation and verification status

Milestone-one source work is complete. The user reported that the demo looks great; agent-side Xcode build/test acceptance remains unverified. The next authorized work is milestone two below.

- Added SwiftUI New Conversation and Conversation Feed views, shared artwork controls, typed message/action models, deterministic fixtures, and an observable main-actor view model. The root owns navigation and feature state.
- Added 27 original Figma image layers (PNG and vector PDF) and six color assets including AccentColor. Provenance and placement are documented in `Docs/FIGMA_ASSETS.md`.
- Added seven focused XCTest cases covering prompt validation, selection, details, editing, session reset, local submission, and asset loading, plus two UI flow tests. These tests have **not** run here.
- `git diff --check` passed. Static checks passed for all catalog JSON, non-empty image files, PNG decoding/CRC, PDF page proportions, named color references, and image callsites. A contact sheet of all imported artwork was inspected. No runtime network URLs or third-party package references were added.
- Follow-up navigator work adds root Markdown documents and the `Docs` group, and replaces synchronized app/test folders with explicit nested groups and file references. All Swift sources are registered once in their own target's Sources phase, and Assets.xcassets is registered once in the app Resources phase. Documentation stays outside build phases. The original iOS 26.5 deployment, bundle identifiers, signing, Swift language mode, and concurrency settings are retained. This is a workaround for folders present in Finder but missing from Xcode; navigator visibility on the Mac still needs confirmation.
- `xcodebuild -version` failed with `command not found` on this Linux host; no Swift toolchain is present either. No compilation, XCTest execution, simulator run, or comparison of the rendered app to Figma has occurred. Those remain required before declaring this milestone verified.
- Settings, stats/history drawer, speaker switching, recording, playback, and regeneration remain unavailable. Translation/transcription are fixture toggles; text edits/submissions only change in-memory data. Nothing survives relaunch.

### Xcode validation checklist

- Build with an iOS SDK supporting the retained 26.5 deployment target; run unit and UI tests.
- At 440-point reference width, compare colors, paper texture, artwork proportions, bubble placement, and action rails with `1:859`, `1:887`, `7:36`, `1:980`, and `7:99`.
- Verify blank/whitespace topics cannot start a chat, suggestion fills the exact Figma prompt, and the keyboard dismisses on navigation.
- Tap audio, learner text, the selected bubble again, and empty feed space. Only one rail should appear at a time, without shifting bubble alignment.
- Toggle the local transcript and translation, edit learner text through the composer, submit with the keyboard, and confirm there is no generated partner response.
- Toggle keyboard/microphone modes; check the composer stays above the keyboard and the feed can scroll with longer content.
- Return via history; confirm the topic is retained and starting again resets the mock feed and selection.
- Check smaller iPhones, landscape, iPad layout, large accessibility text, Reduce Motion, and VoiceOver labels/order. Real scroll indicators appear only when there is scrollable content.
- Confirm no microphone permission prompt or network requests occur. Settings, stats, recording, playback, and regeneration are intentionally unavailable.

### Product decisions confirmed 2026-10-27

1. An initial prompt is required. Users must supply one or click prompt generation; the current suggestion button supplies a deterministic mock prompt. The original optional wording was a design-copy mistake, and the placeholder now reflects the required input.
2. Leave the coffee/turtle mock mistranslation unchanged for now, as requested.
3. Replace the temporary history-to-New-Conversation mapping with the history drawer. The user approved a “新对话” row at the top because the Figma drawer has no create control.
4. Use Apple system fonts rather than Inter in the new history/settings views, as approved, with scaled text sizes.
5. Preserve the voice/text bubble palette. The user clarified that appearance follows the communication method used to send each message, rather than the current composer mode. Retain the reply-length labels from Figma, including “复杂”; no copy rewrite is part of this milestone.

## Milestone 2 — conversation history and conversation settings

Authorized scope: the history drawer (`1:914`) and conversation settings (`2:56`), using local state and the existing visual design. General settings and conversation adjustment remain future work. Stop after these two flows are ready for testing.

- [x] Inspect high-fidelity Figma context and screenshots for both flows.
- [x] Record the required-prompt decision, retained mock translation, approved New Conversation row, and system-font choice.
- [x] Add typed settings and session models with per-conversation in-memory messages/settings.
- [x] Open history from both screens, select/reopen an entry, dismiss with the red back control or scrim, and start a blank conversation via “新对话”.
- [x] Preserve the navy drawer, pale selected row, blue selection text, red back artwork, cream paper background, and tan/green settings capsules.
- [x] Enable tone, vocabulary, and reply-length selections; apply changes immediately and restore them with their history entry.
- [x] Register new source/test files in the explicit Xcode groups and build phases.
- [x] Add focused session-isolation tests and update UI flow tests for the new navigation.
- [x] Finish static project/asset checks and document validation limits.
- [ ] Build, run XCTest/UI tests, and compare both new views with Figma in Xcode.

History is intentionally in memory for this milestone and resets on app relaunch. It starts with the Figma “乌龟” and B–J fixture rows; those rows reuse the existing turtle mock messages. Newly started conversations appear first with their own identity. Committed edits/submitted messages and settings are retained while switching entries; unsent drafts and message-action selection are cleared. Settings chosen before starting a conversation apply to that new conversation. “新对话” resets settings to casual/medium/medium.

Both gear controls open Conversation Settings directly in this milestone. No general-settings intermediary or conversation-adjustment screen is implemented. Settings do not change the canned AI reply: no backend service is connected.

### Milestone-two validation status

- Static project checks passed: 15 app Swift files, three unit-test source files, and three UI-test source files are each registered once in the correct target. The asset catalog remains registered once in app Resources. Existing build configurations, target identifiers, signing, deployment target, and concurrency settings are unchanged.
- Static asset checks passed for all 30 image assets and 12 color assets: catalog JSON, non-empty PNG/PDF files, PNG integrity, PDF page proportions, Swift callsites, and named-color references. The new SVG artwork was downloaded from Figma and converted to vector PDF; the drawer/settings back art was verified identical before reuse. No runtime network client, temporary Figma URL, or third-party package reference was added.
- Added five session/history unit tests; added two UI flow tests and updated the earlier navigation test for the new drawer. These tests have not run here.
- The simulator build command failed with `xcodebuild: command not found` (exit 127). No compilation or simulator comparison is claimed. The following Xcode checklist remains the acceptance step.
- User-reported Mac test attempts: `XiaoLiaoUITests-Runner` on the iPhone 17 Pro simulator failed to initialize for UI testing with `Timed out waiting for AX loaded notification`, including a retry with parallel execution disabled. This is a runner initialization timeout, with no individual failed assertion supplied. UI-test acceptance remains pending. Collect exact Xcode/runtime versions and Activity Monitor readings if continuing diagnosis; neither limited RAM nor app code has been established as the cause. Do not change app assertions or mark tests passed based on this report. The user accepted proceeding with manual checks and has now authorized milestone three.

Milestone-two source implementation is ready for testing. The user reported that the flows look good and subsequently authorized milestone three. General settings, statistics, persisted history, and backend integration remain future work.

### Milestone-two Xcode checks

- Confirm Features, Design, the two new views, and the new history unit-test file appear in the navigator. Build with the retained iOS 26.5 deployment settings and run all tests.
- From New Conversation, check required prompt copy and generation; open/close history without losing the typed prompt. Open conversation settings, change all three controls, return, and start a conversation.
- From the feed, open history and verify the current entry is highlighted. Switch to B, change its settings, then reopen the earlier entry and confirm its messages/settings remain independent.
- Edit/send a local learner message, switch away and back, and confirm the committed content is retained. Start “新对话” and confirm the prompt is empty, Chat is disabled, settings are defaults, and previous entries remain available.
- Dismiss history using both the red arrow and outside scrim; check neither action activates controls beneath the drawer.
- Compare the drawer with `1:914` and settings with `2:56`, allowing only the approved New Conversation row/system-font substitutions and real safe-area layout.
- Verify history scrolling, small iPhones, landscape, iPad, large accessibility text, VoiceOver focus/selected values, and Reduce Motion. Verify settings Back returns to the correct originating screen.
- Relaunch and confirm the documented mock reset; persistence belongs to a future milestone. Recording, stats, and live AI generation must remain unavailable.

### Follow-up fixes — message appearance and editing

The user reported two issues: changing composer mode recolored earlier messages, and older learner messages could still be edited.

- [x] Store immutable sender/send-method metadata on messages. Mark the existing green learner fixture as a spoken response displayed as text; mark keyboard submissions as typed.
- [x] Use the message's send method for bubble/text colors. Preserve that method when editing or reopening history.
- [x] Show Edit only for the most recent learner message. Enforce eligibility in the view model both when an edit starts and when it commits; partner replies do not change which learner message is latest.
- [x] Add regression coverage for mixed communication methods, history restoration, editing the latest message, rejecting older/partner edits, and preserving the method when editing a spoken response.
- [ ] Build and run the tests in Xcode; check colors and contextual actions in the simulator.

Xcode checks: switch to keyboard input and back before sending anything; the existing green response must stay green. Send a typed message and switch to voice; the new message must remain white while the original remains green. Select both learner messages: Edit must appear only beside the latest one. Edit it and reopen the conversation through history; colors and edit eligibility must remain correct. Recording remains unavailable.

Validation: source review and `git diff --check` completed; the Xcode project file is unchanged because the changes and regression tests use existing registered files. The build attempt failed with `xcodebuild: command not found` (exit 127). The new tests and simulator checks have not run here.

## Milestone 3 — local audio practice

Authorized 2026-10-28. Implement real local recording/review/playback with Apple audio APIs, preserving the existing Figma feed. Stop after the flow is ready for Xcode/device testing. No live AI or speech recognition is included.

### Confirmed design and scope

- Inspected high-fidelity context and screenshots for recording (`2:121`), playback (`2:303`), voice editing (`2:432`), loading (`2:505`), and sent voice (`2:537`).
- The user approved reusing the designed Pause/waveform/Send row for review: Pause finalizes the current audio, tapping the waveform previews/pauses it, tapping Pause again resumes, and switching to the keyboard or leaving the feed discards the unsent recording. No new screen or review sheet is added.
- The user approved audio-only recordings displayed in the existing green learner bubble as “语音消息 · [duration]”. No invented English transcript, translation, synthesized fixture audio, or partner response is produced. Existing fixture details remain as before; their playback stays unavailable because they have no audio file.
- Only the latest learner message offers Edit. Real recorded messages record a replacement through the designed row; cancellation/failure preserves the original. Existing text and fixture-transcript edits keep using the text composer.
- The partner-loading bubble in `2:505` is reserved for actual service integration. Local processing is shown in the recording row only while permission/file finalization is genuinely pending. No artificial response-loading delay is introduced.

### Implementation

- [x] Add an observable main-actor audio controller using `AVAudioRecorder`, `AVAudioPlayer`, `AVAudioApplication` microphone permission, and `AVAudioSession` lifecycle handling.
- [x] Record mono PCM into app-owned temporary CAF files. Pausing closes the current segment; resuming starts another. Join segments in order using fixed-size buffers off the main actor so preview/send reads a finalized file without loading the entire clip into memory.
- [x] Add real recording duration and level feedback, inline review, pause/resume playback, Send, keyboard/navigation cancellation, and latest-recording replacement.
- [x] Retain committed clips through in-memory history switches. Delete cancelled segments, superseded reviews, and replaced clips; clear previous-run scratch files on the next controller initialization. History and clips are not restored on relaunch.
- [x] Handle denied microphone permission with a native alert and system-settings link. Handle recording, finalization, and playback failures without committing a fabricated message.
- [x] Cancel pending permission/finalization work on navigation/backgrounding/interruption. Stop playback on backgrounding, selected-device removal, and audio-service loss/reset. Never resume automatically.
- [x] Import the four original Figma Pause/Send/waveform layers, preserving their proportions, and reuse the existing paper, rings, message bubble, and inline timeline assets.
- [x] Register the audio controller and test source in explicit Xcode groups/Sources phases. Add `NSMicrophoneUsageDescription` to app Debug and Release only; preserve the existing build/signing/deployment/concurrency settings.
- [x] Add nine focused audio tests covering denied/cancelled permission, interruption while permission is pending, segment order/sample preservation, invalid audio, history retention and message colors, stale-session rejection, atomic replacement/cancellation, and latest-message editing. Extend the existing UI smoke flow to check that recording is enabled and recording-row actions are initially absent. No real microphone or playback is invoked by these automated tests.
- [ ] Build, run tests, and compare rendering in Xcode; verify the real recording/playback lifecycle on an iPhone.

### Validation status

The build command was attempted here and failed with `xcodebuild: command not found` (exit 127). No successful compilation, XCTest run, simulator rendering, or device audio test is claimed. The existing Mac UI-test runner initialization timeout remains unresolved; it is separate from a failed app assertion. Source/project/asset checks and the manual device checklist below are the handoff, not a replacement for runtime validation.

Static checks passed: the Xcode project parses, all 16 app/four unit-test/three UI-test Swift sources are registered once in their own targets, the asset catalog is registered once, and existing build settings are unchanged apart from the two app microphone usage descriptions. All image-catalog JSON and referenced files were checked; the four new PDFs decode with their original viewport dimensions and were visually inspected. New artwork callsites retain those dimensions and the designed layer composition. `git diff --check` passed. No third-party package, speech service, network client, or background-audio entitlement was added.

Apple API references: [recording](https://developer.apple.com/documentation/avfaudio/avaudiorecorder), [microphone permission](https://developer.apple.com/documentation/avfaudio/avaudioapplication), [audio files and PCM buffers](https://developer.apple.com/documentation/avfaudio/avaudiofile), [interruptions](https://developer.apple.com/documentation/avfaudio/handling-audio-interruptions).

### Xcode and device checklist

1. Build with the retained iOS 26.5 deployment target. Confirm the new controller/test file and four image assets appear in Xcode. Verify the built app's Info contains the microphone usage description in both build configurations. Run `XiaoLiaoTests`, including `ConversationAudioTests`; retry the UI suite when its runner can initialize.
2. Launch a conversation: there must be no microphone prompt until Record is tapped. Deny permission, confirm the explanation and Settings link, then grant permission and retry. Keep a working keyboard path when permission/input hardware is unavailable.
3. Record a distinct sentence, Pause, and tap the green waveform to preview it. Tap again to pause playback. Resume recording and say a second sentence; Pause and confirm playback contains both sentences in order with no speech lost or duplicated. Repeat pause/resume more than once.
4. Send while recording and while paused. Confirm exactly one green “语音消息 · [duration]” bubble is appended, its Play action plays the actual clip, the inline timeline advances, and no fake transcript, translation, or AI reply appears. The original fixture playback must remain disabled.
5. Send a typed reply and switch composer modes: previously sent voice/typed colors must stay fixed. Only the latest learner message offers Edit. Re-record the latest audio; cancel via keyboard or navigation and confirm the original still plays. Then send a replacement and confirm the same message is updated once and retained in history.
6. Switch history entries and settings; committed recordings must remain playable in their own entry. Start New Conversation; previous entries stay intact. Unsent recordings/replacements must be discarded on keyboard switching, history/settings navigation, or leaving the feed, including while permission or file processing is pending.
7. Background/lock the phone during recording and playback; test an incoming interruption and disconnecting headphones. Audio must stop and must not restart automatically. Return and record/play again. Inspect for a stuck recording row, duplicate send, or a lost committed clip after an interruption or permission failure.
8. Compare the recording and playback layouts to `2:121`, `2:303`, and `2:432` on large/small iPhones, landscape, Dynamic Type, VoiceOver, and Reduce Motion. Confirm 44-point action targets and accessible duration/play/pause/resume/send labels.
9. Relaunch and confirm history resets. Recordings are temporary current-run data; persistence is milestone four. Physical-device microphone/output behavior still needs testing even if the simulator works.

Stop after milestone three. Open runtime questions: actual microphone/input routing on the user's cloud Mac, physical-device interruption behavior, and visual/accessibility comparison in Xcode. Speech recognition and live partner audio remain future integration work.

## Milestone 4 — persisted history and designed statistics (future)

Add persistence and the existing conversation/all-time statistics views once metric definitions are confirmed. Acceptance: sessions survive relaunch and local statistics match defined sample calculations; the app and tests build.

## Milestone 5 — service integration (future; requires a new request)

Agree on the backend contract, privacy behavior, authentication requirements, streaming/error states, and secret handling before adding AI or speech services. Keep credentials off-device and preserve the approved UI. Acceptance: an explicitly approved end-to-end conversation flow builds and passes integration checks. No backend AI work belongs to milestone one.
