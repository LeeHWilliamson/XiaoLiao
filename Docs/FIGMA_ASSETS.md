# Figma artwork provenance

Source file: [project_V2](https://www.figma.com/design/jVSZ8R37YkVCJOC32lLmMR/project_V2?node-id=1-3). Retrieved 2026-10-26 through Figma design context.

Original PNG fills are bundled unchanged. Original SVG layers were converted to vector PDF using the host's librsvg/Cairo, retaining their root viewport dimensions and proportions. These conversion tools are not app dependencies. No full-screen mockup export is used as UI. Invisible fills and texture layers hidden behind opaque green fills are omitted.

`FigmaArtwork.swift` records intrinsic sizes, and `FigmaImage` preserves aspect ratios. `ArtworkControls.swift` composes the separate ring/glyph exports. Microphone artwork originates in a 53-point control; other header glyphs originate in 64-point controls. Active transcript/translation states tint only the glyph white, above a green fill, as shown in the selected V2 frames.

| Asset | Source node | Export dimensions | App placement |
| --- | --- | --- | --- |
| PaperTexture | [`1:860`](https://www.figma.com/design/jVSZ8R37YkVCJOC32lLmMR/project_V2?node-id=1-860) | 1024 × 1024 | PaperBackground; 3% opacity, fill/crop |
| ControlRing | [`1:868`](https://www.figma.com/design/jVSZ8R37YkVCJOC32lLmMR/project_V2?node-id=1-868) | 64 × 64 | ConversationHeader and composer controls |
| HistoryGlyph | [`1:870`](https://www.figma.com/design/jVSZ8R37YkVCJOC32lLmMR/project_V2?node-id=1-870) | 32.0007 × 32.0007 | Header leading control |
| StatsGlyph | [`1:875`](https://www.figma.com/design/jVSZ8R37YkVCJOC32lLmMR/project_V2?node-id=1-875) | 31.9977 × 31.9977 | Header center control |
| SettingsGlyph | [`1:880`](https://www.figma.com/design/jVSZ8R37YkVCJOC32lLmMR/project_V2?node-id=1-880) | 32.001 × 32.001 | Header trailing control |
| SuggestRing | [`1:883`](https://www.figma.com/design/jVSZ8R37YkVCJOC32lLmMR/project_V2?node-id=1-883) | 56 × 56 | Topic suggestion control |
| SuggestGlyph | [`1:885`](https://www.figma.com/design/jVSZ8R37YkVCJOC32lLmMR/project_V2?node-id=1-885) | 27.8466 × 28.0017 | Topic suggestion control |
| RecordSurface | [`7:103`](https://www.figma.com/design/jVSZ8R37YkVCJOC32lLmMR/project_V2?node-id=7-103) | 494 × 162 | Voice composer, 247 × 81 including shadow |
| AudioOval | [`7:106`](https://www.figma.com/design/jVSZ8R37YkVCJOC32lLmMR/project_V2?node-id=7-106) | 209 × 86 | Partner audio bubble, 209 × 86 |
| AudioTail | [`7:107`](https://www.figma.com/design/jVSZ8R37YkVCJOC32lLmMR/project_V2?node-id=7-107) | 17.2822 × 23.3026 | Partner bubble lower-left; rotated −154.56° |
| SpeakingGlyph | [`7:108`](https://www.figma.com/design/jVSZ8R37YkVCJOC32lLmMR/project_V2?node-id=7-108) | 51.19 × 51.2245 | Inside partner audio bubble |
| TextTail | [`7:112`](https://www.figma.com/design/jVSZ8R37YkVCJOC32lLmMR/project_V2?node-id=7-112) | 17.2822 × 23.3026 | Learner bubble lower-right; rotated 150° |
| ActionRing | [`7:137`](https://www.figma.com/design/jVSZ8R37YkVCJOC32lLmMR/project_V2?node-id=7-137) | 40.6344 × 40.6344 | Learner playback action |
| PlayGlyph | [`7:139`](https://www.figma.com/design/jVSZ8R37YkVCJOC32lLmMR/project_V2?node-id=7-139) | 19.233 × 21.0005 | Learner playback action |
| EditRing | [`7:128`](https://www.figma.com/design/jVSZ8R37YkVCJOC32lLmMR/project_V2?node-id=7-128) | 40.639 × 40.639 | Learner edit action |
| EditGlyph | [`7:130`](https://www.figma.com/design/jVSZ8R37YkVCJOC32lLmMR/project_V2?node-id=7-130) | 21.0005 × 21.0005 | Learner edit action |
| TranslateRing | [`7:132`](https://www.figma.com/design/jVSZ8R37YkVCJOC32lLmMR/project_V2?node-id=7-132) | 43.8146 × 43.8146 | Learner translation action |
| TranslateGlyph | [`7:134`](https://www.figma.com/design/jVSZ8R37YkVCJOC32lLmMR/project_V2?node-id=7-134) | 26 × 26 | Learner translation action |
| KeyboardGlyph | [`7:143`](https://www.figma.com/design/jVSZ8R37YkVCJOC32lLmMR/project_V2?node-id=7-143) | 32.0029 × 20.5537 | Voice composer trailing control |
| VoiceModeGlyph | [`7:147`](https://www.figma.com/design/jVSZ8R37YkVCJOC32lLmMR/project_V2?node-id=7-147) | 32.001 × 29.5507 | Composer leading control |
| AudioActionRing | [`5:86`](https://www.figma.com/design/jVSZ8R37YkVCJOC32lLmMR/project_V2?node-id=5-86) | 40.6344 × 40.6344 | Partner action rail |
| TranscribeGlyph | [`5:88`](https://www.figma.com/design/jVSZ8R37YkVCJOC32lLmMR/project_V2?node-id=5-88) | 17.3061 × 21.0009 | Partner transcription action |
| AudioTranslateGlyph | [`5:92`](https://www.figma.com/design/jVSZ8R37YkVCJOC32lLmMR/project_V2?node-id=5-92) | 21.0028 × 15.1819 | Partner translation action |
| RepeatGlyph | [`5:96`](https://www.figma.com/design/jVSZ8R37YkVCJOC32lLmMR/project_V2?node-id=5-96) | 21.0006 × 17.7362 | Partner regeneration action |
| MicrophoneGlyph | [`1:1075`](https://www.figma.com/design/jVSZ8R37YkVCJOC32lLmMR/project_V2?node-id=1-1075) | 14.265 × 26.5008 | Text composer trailing control |
| TranscriptDot | [`2:218`](https://www.figma.com/design/jVSZ8R37YkVCJOC32lLmMR/project_V2?node-id=2-218) | 17 × 15 | Inline transcript timeline |
| TranscriptLine | [`2:217`](https://www.figma.com/design/jVSZ8R37YkVCJOC32lLmMR/project_V2?node-id=2-217) | 182 × 2 | Inline transcript timeline |

The RecordSurface PNG is exported at 2× resolution (494 × 162 pixels) and displayed at 247 × 81 points, including its shadow. The paper texture is the design's square source fill, cropped to the screen at 3% opacity.

UI is laid out within real device safe areas. The mockup's black device outline, rounded device mask, and decorative scrollbar are not bundled. A real scroll view supplies scrolling and indicators when needed.

Validation here checks asset existence, non-empty contents, image decoding, PDF page proportions, catalog references, and source callsites. The XCTest artwork check also loads every asset via UIImage on iOS. Effective rendering, tint, alignment, and tap regions still require the Xcode simulator comparison described in PLAN.md.

## Milestone two — history and conversation settings

Retrieved 2026-10-27 from history frame [`1:914`](https://www.figma.com/design/jVSZ8R37YkVCJOC32lLmMR/project_V2?node-id=1-914) and conversation-settings frame [`2:56`](https://www.figma.com/design/jVSZ8R37YkVCJOC32lLmMR/project_V2?node-id=2-56).

| Asset | Source node | Export dimensions | App placement |
| --- | --- | --- | --- |
| BackRing | `1:1167` | 64 × 64 | Settings Back and history Close |
| BackGlyph | `1:1169` | 17.4473 × 32.0012 | Centered inside BackRing |
| SettingsRule | `2:63` | 314 × 1 | Below each settings section title |

The drawer's source ring/glyph (`1:929`, `1:931`) were downloaded separately and verified byte-for-byte identical to the settings back artwork before reuse. Original SVGs were converted to vector PDF at their root dimensions using the same host librsvg/Cairo conversion as milestone one. No converter or font dependency was added to the app.

The existing paper texture and watermark are reused. History colors are `#182332` (background), `#EDF2FF` (foreground and selected-row fill), `#174CD7` (selected-row text), `#E6DBC2` at 69% opacity (outside scrim), and `#B7C9FF` at 25% opacity (title glow). Settings use the existing `#D8C9A8` prompt color at 75% opacity and `#8FAA76` for selected options. These six additional named color assets leave AccentColor unchanged.

History uses a native plain List for rows and separators, with the Figma pale trailing border. The settings capsules are custom branded controls: tan/green colors and 77-point height come from the Figma frame rather than the system segmented-control appearance. The user approved Apple system fonts in place of Inter and one “新对话” history row; other labels and visual patterns are retained. Runtime rendering still needs comparison in Xcode.
