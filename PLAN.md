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

Milestone-one source work is complete. Stop here; Xcode acceptance remains pending.

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

### Known design questions

1. The initial prompt says a topic is optional, but the empty frame disables “聊天”. Milestone one follows the visible disabled state; confirm whether future sessions should allow an empty prompt.
2. Figma's learner translation is “我今天喝了杯咖啡”, which does not translate the turtle message. Preserve the supplied fixture for now; confirm corrected copy before implementing real translations.
3. The temporary history-to-New-Conversation mapping is explicitly approved. Replace it with the designed history drawer only in a later, authorized milestone.
4. Selected frames use different font sizes and green/white bubbles across voice/text modes. Follow the base feed for voice mode and `typed_message` for text mode; confirm final design normalization later.

## Milestone 2 — remaining designed local flows (future)

Implement the existing history drawer, general/conversation settings, and conversation adjustment screen from Figma. Keep mock data local; define each screen's state and navigation from its frame before coding. Acceptance: the app builds and these approved flows work with local state. No additional screens without design references.

## Milestone 3 — local audio practice (future)

Implement the designed recording, review, playback, and loading states with Apple audio APIs and explicit microphone permission handling. Confirm replay/edit behavior from Figma before implementation. Acceptance: recording/playback lifecycle works on device, with cancellation and interruption handling, and the app builds with its tests passing.

## Milestone 4 — local history and designed statistics (future)

Add persistence and the existing conversation/all-time statistics views once metric definitions are confirmed. Acceptance: sessions survive relaunch and local statistics match defined sample calculations; the app and tests build.

## Milestone 5 — service integration (future; requires a new request)

Agree on the backend contract, privacy behavior, authentication requirements, streaming/error states, and secret handling before adding AI or speech services. Keep credentials off-device and preserve the approved UI. Acceptance: an explicitly approved end-to-end conversation flow builds and passes integration checks. No backend AI work belongs to milestone one.
