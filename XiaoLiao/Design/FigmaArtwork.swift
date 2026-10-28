import SwiftUI

/// Intrinsic Figma export dimensions; preserve each layer's aspect ratio.
enum FigmaArtwork: String, CaseIterable {
    case paperTexture = "PaperTexture"
    case controlRing = "ControlRing"
    case historyGlyph = "HistoryGlyph"
    case statsGlyph = "StatsGlyph"
    case settingsGlyph = "SettingsGlyph"
    case suggestRing = "SuggestRing"
    case suggestGlyph = "SuggestGlyph"
    case recordSurface = "RecordSurface"
    case audioOval = "AudioOval"
    case audioTail = "AudioTail"
    case speakingGlyph = "SpeakingGlyph"
    case textTail = "TextTail"
    case actionRing = "ActionRing"
    case playGlyph = "PlayGlyph"
    case editRing = "EditRing"
    case editGlyph = "EditGlyph"
    case translateRing = "TranslateRing"
    case translateGlyph = "TranslateGlyph"
    case keyboardGlyph = "KeyboardGlyph"
    case voiceModeGlyph = "VoiceModeGlyph"
    case audioActionRing = "AudioActionRing"
    case transcribeGlyph = "TranscribeGlyph"
    case audioTranslateGlyph = "AudioTranslateGlyph"
    case repeatGlyph = "RepeatGlyph"
    case microphoneGlyph = "MicrophoneGlyph"
    case transcriptDot = "TranscriptDot"
    case transcriptLine = "TranscriptLine"
    case backRing = "BackRing"
    case backGlyph = "BackGlyph"
    case settingsRule = "SettingsRule"

    var size: CGSize {
        switch self {
        case .paperTexture: CGSize(width: 1024, height: 1024)
        case .controlRing: CGSize(width: 64, height: 64)
        case .historyGlyph: CGSize(width: 32.0007, height: 32.0007)
        case .statsGlyph: CGSize(width: 31.9977, height: 31.9977)
        case .settingsGlyph: CGSize(width: 32.001, height: 32.001)
        case .suggestRing: CGSize(width: 56, height: 56)
        case .suggestGlyph: CGSize(width: 27.8466, height: 28.0017)
        case .recordSurface: CGSize(width: 247, height: 81)
        case .audioOval: CGSize(width: 209, height: 86)
        case .audioTail: CGSize(width: 17.2822, height: 23.3026)
        case .speakingGlyph: CGSize(width: 51.19, height: 51.2245)
        case .textTail: CGSize(width: 17.2822, height: 23.3026)
        case .actionRing: CGSize(width: 40.6344, height: 40.6344)
        case .playGlyph: CGSize(width: 19.233, height: 21.0005)
        case .editRing: CGSize(width: 40.639, height: 40.639)
        case .editGlyph: CGSize(width: 21.0005, height: 21.0005)
        case .translateRing: CGSize(width: 43.8146, height: 43.8146)
        case .translateGlyph: CGSize(width: 26, height: 26)
        case .keyboardGlyph: CGSize(width: 32.0029, height: 20.5537)
        case .voiceModeGlyph: CGSize(width: 32.001, height: 29.5507)
        case .audioActionRing: CGSize(width: 40.6344, height: 40.6344)
        case .transcribeGlyph: CGSize(width: 17.3061, height: 21.0009)
        case .audioTranslateGlyph: CGSize(width: 21.0028, height: 15.1819)
        case .repeatGlyph: CGSize(width: 21.0006, height: 17.7362)
        case .microphoneGlyph: CGSize(width: 14.265, height: 26.5008)
        case .transcriptDot: CGSize(width: 17, height: 15)
        case .transcriptLine: CGSize(width: 182, height: 2)
        case .backRing: CGSize(width: 64, height: 64)
        case .backGlyph: CGSize(width: 17.4473, height: 32.0012)
        case .settingsRule: CGSize(width: 314, height: 1)
        }
    }
}

struct FigmaImage: View {
    let artwork: FigmaArtwork

    var body: some View {
        Image(artwork.rawValue)
            .renderingMode(.original)
            .resizable()
            .scaledToFit()
            .accessibilityHidden(true)
    }
}
