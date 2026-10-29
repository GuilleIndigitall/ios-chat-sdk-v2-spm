import ChatCore
import SwiftUI

#if os(iOS)
import IndigitallDesign
import IndigitallModels

struct INDChatKitThemeModifier: ViewModifier {
    let theme: INDChatTheme

    func body(content: Content) -> some View {
        content
            .environment(\.theme, INDChatKitLegacyTheme(theme: theme))
            .ccTheme(chatKitTheme)
    }

    private var chatKitTheme: IndigitallTheme {
        var kitTheme = IndigitallTheme()
        kitTheme.colors.blue = Color(hex: theme.primaryColorHex)
        kitTheme.colors.lightGreen = Color(hex: theme.businessBubbleColorHex)
        kitTheme.colors.white = Color(hex: theme.contactBubbleColorHex)
        kitTheme.colors.black = Color(hex: theme.textColorHex)
        kitTheme.colors.gray2 = Color(hex: theme.mutedTextColorHex)
        kitTheme.colors.red = Color(hex: theme.errorColorHex)
        return kitTheme
    }
}

private struct INDChatKitLegacyTheme: ThemeProviding {
    let theme: INDChatTheme

    func color(for style: Theme.Style) -> Color {
        switch style {
        case .primary, .info, .messageRead:
            Color(hex: theme.primaryColorHex)
        case .background:
            Color(hex: theme.backgroundColorHex)
        case .surface, .incomingBubble:
            Color(hex: theme.contactBubbleColorHex)
        case .outgoingBubble:
            Color(hex: theme.businessBubbleColorHex)
        case .textPrimary, .incomingBubbleText, .outgoingBubbleText:
            Color(hex: theme.textColorHex)
        case .textSecondary, .textTertiary, .bubbleTimestamp, .messageSent:
            Color(hex: theme.mutedTextColorHex)
        case .error, .messageError:
            Color(hex: theme.errorColorHex)
        default:
            DefaultTheme().color(for: style)
        }
    }

    func font(for style: Theme.Font) -> FontStyle {
        DefaultTheme().font(for: style)
    }

    func gradient(for style: Theme.Gradient) -> LinearGradient {
        DefaultTheme().gradient(for: style)
    }
}
#else
struct INDChatKitThemeModifier: ViewModifier {
    let theme: INDChatTheme

    func body(content: Content) -> some View { content }
}
#endif
