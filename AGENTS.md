# XiaoLiao (小聊)

Native SwiftUI iOS app for Chinese speakers practicing conversational English.

## Repository

- `XiaoLiao.xcodeproj`: existing Xcode project; app, XCTest, and UI-test targets.
- `XiaoLiao/XiaoLiaoApp.swift`: app entry point.
- `XiaoLiao/ContentView.swift`: root navigation and shared feature state.
- `XiaoLiao/Features/Conversation/`: conversation models, local fixtures, view model, and views.
- `XiaoLiao/Design/`: shared colors, background, and artwork controls.
- `XiaoLiao/Assets.xcassets`: bundled Figma artwork and colors.
- `XiaoLiaoTests/`, `XiaoLiaoUITests/`: behavior and navigation tests.
- `PLAN.md`: milestones, validation status, and open design questions.

The project uses explicit Xcode groups and file references following a workaround for source folders missing from the Project navigator. When adding Swift files, add their file references to the appropriate group and register each once in its target's Sources build phase. Register asset catalogs once in Resources; keep project documentation out of build phases. Avoid other unnecessary project-file edits. Preserve the existing iOS 26.5 deployment target, bundle identifiers, signing, Swift language mode, and concurrency settings unless explicitly asked to change them.

## Architecture and conventions

- Use SwiftUI and lightweight MVVM. Keep navigation in the root, presentation in views, state transitions in the feature view model, and mock content in a separate fixture.
- Use value-type, identifiable messages and typed enums for actions and UI state. Use `@Observable` for the view model, `@State` for its owner, and `@Bindable` where views edit its properties. UI state belongs on the main actor.
- Use feature directories; extract shared controls only when actually reused. Avoid speculative repositories, dependency containers, coordinators, and service protocols.
- Keep data local and deterministic initially. No backend, AI API, authentication, network service, API keys, analytics, or persistence in milestone one. Do not imply that canned content is generated or translated live.
- Add no third-party dependencies unless necessary. Prefer Apple frameworks. Bundled PDF artwork is a build asset, not a runtime rendering dependency.
- Use native layout, scrolling, text input, safe areas, and navigation. Preserve custom Figma artwork rather than replacing it with similar SF Symbols. Use SF Symbols only where the design names them.
- Centralize brand colors. Use semantic text styles or scaled metrics for custom display sizes; provide VoiceOver labels, selection state, and at least 44-point action targets. Respect Reduce Motion. Do not bake a whole screen screenshot into the UI.
- Add focused tests for consequential state transitions and navigation. Never claim tests passed or compilation succeeded unless the relevant command actually ran successfully.
- Keep changes scoped to the requested milestone. Stop after milestone one until the user requests further work.

## Design source and constraints

[Figma project_V2, mockup page](https://www.figma.com/design/jVSZ8R37YkVCJOC32lLmMR/project_V2?node-id=1-3)

Primary references:

| Frame | Node | Purpose |
| --- | --- | --- |
| New_conversation_init | `1:859` | Empty topic field, disabled chat button |
| new_convo_with_prompt | `1:887` | Filled topic field, enabled chat button |
| Conversation Feed | `7:36` | Default voice-mode feed |
| Conversation Feed | `1:980` | Selected partner audio and actions |
| Conversation Feed | `7:99` | Selected learner text and actions |
| typed_message | `1:1035` | Existing text input pattern |
| V2 • message_transcribe | `2:175` | Inline mock transcript |
| V2 • translate_own_message | `2:371` | Inline mock translation |

Preserve the cream paper texture, brown outlined controls, green text bubbles, red voice control, Chinese UI copy, English messages, spacing, and adjacent action rails. Device outline/corner mask and status/home indicators in the mockup are device chrome, not app artwork. Use real scroll indicators; do not draw a fake scrollbar for a short feed.

Do not invent screens, tab bars, menus, sheets, or interactions. For missing design states, inspect Figma or request specific screenshots instead of guessing. The user explicitly chose the existing top-left history control as the temporary route back to New Conversation; do not build the history drawer in milestone one. Keep settings/stats, recording, playback, and regeneration visibly present but unavailable until their milestone is authorized. Do not simulate successful recording or playback.

Asset provenance is recorded in `Docs/FIGMA_ASSETS.md`. Never use temporary Figma URLs at runtime. Preserve original image proportions and asset-layer composition.

## Validation

On a Mac with an SDK/runtime supporting the existing deployment target:

```sh
xcodebuild -list -project XiaoLiao.xcodeproj
xcodebuild -project XiaoLiao.xcodeproj -scheme XiaoLiao -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
xcodebuild -showdestinations -project XiaoLiao.xcodeproj -scheme XiaoLiao
# Replace the destination ID with an available iOS 26.5+ simulator.
xcodebuild -project XiaoLiao.xcodeproj -scheme XiaoLiao -destination 'platform=iOS Simulator,id=SIMULATOR_UUID' test
```

Check the requested screens against their Figma frames on a large iPhone, then check a smaller iPhone, landscape, Dynamic Type, keyboard avoidance, and VoiceOver. Linux source/asset checks cannot substitute for an Xcode build or simulator comparison.
