import ChatCore
import SwiftUI
#if os(iOS)
import IndigitallDesign
import UIKit
#endif

public struct IndigitallChat: View {
    private let configuration: INDChatConfiguration
    @StateObject private var store: INDChatStore

    public init(configuration: INDChatConfiguration) {
        self.configuration = configuration
        _store = StateObject(wrappedValue: INDChatStore(configuration: configuration))
    }

    public var body: some View {
        INDChatContent(
            store: store,
            configuration: configuration,
            showsInlinePresentation: !configuration.fullscreen
        )
        .modifier(INDChatFullscreenPresentationModifier(
            store: store,
            configuration: configuration
        ))
    }
}

struct INDChatContent: View {
    @ObservedObject var store: INDChatStore
    let configuration: INDChatConfiguration
    var showsInlinePresentation = true
    @State private var isWelcomeLabelDismissed = false
    @State private var autoOpenTask: Task<Void, Never>?

    var body: some View {
        ZStack(alignment: alignment) {
            if store.state.isOpen {
                if showsInlinePresentation {
                    INDChatPresentation(store: store, configuration: configuration)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            } else {
                VStack(alignment: configuration.launcherPosition == .bottomLeading ? .leading : .trailing, spacing: 12) {
                    if showsWelcomeLabel {
                        INDChatWelcomeLabelView(
                            welcomeLabel: configuration.welcomeLabel!,
                            theme: configuration.theme,
                            configuration: configuration,
                            open: openFromLauncher,
                            dismiss: dismissWelcomeLabel
                        )
                    }
                    INDChatLauncher(theme: configuration.theme, configuration: configuration, open: openFromLauncher)
                }
                .padding(.horizontal, configuration.launcherHorizontalOffset)
                .padding(.vertical, configuration.launcherVerticalOffset)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: alignment)
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: store.state.isOpen)
        .onChange(of: store.state.isOpen) { isOpen in
            if isOpen { dismissWelcomeLabel() }
        }
        .task { scheduleAutoOpen() }
        .onDisappear { autoOpenTask?.cancel() }
    }

    private var alignment: Alignment {
        configuration.launcherPosition == .bottomLeading ? .bottomLeading : .bottomTrailing
    }

    private var showsWelcomeLabel: Bool {
        !isWelcomeLabelDismissed && configuration.welcomeLabel != nil
    }

    private func openFromLauncher() {
        autoOpenTask?.cancel()
        dismissWelcomeLabel()
        store.open()
    }

    private func dismissWelcomeLabel() {
        autoOpenTask?.cancel()
        isWelcomeLabelDismissed = true
    }

    private func scheduleAutoOpen() {
        guard !configuration.initiallyOpen, let delay = configuration.autoOpenDelay else { return }
        autoOpenTask?.cancel()
        autoOpenTask = Task {
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            openFromLauncher()
        }
    }
}

private struct INDChatFullscreenPresentationModifier: ViewModifier {
    @ObservedObject var store: INDChatStore
    let configuration: INDChatConfiguration

    func body(content: Content) -> some View {
        #if os(iOS)
        content.fullScreenCover(isPresented: isPresented) {
            INDChatPanel(store: store, configuration: configuration)
        }
        #else
        content
        #endif
    }

    #if os(iOS)
    private var isPresented: Binding<Bool> {
        Binding(
            get: { configuration.fullscreen && store.state.isOpen },
            set: { isPresented in
                if !isPresented { store.close() }
            }
        )
    }
    #endif
}

private struct INDChatPresentation: View {
    @ObservedObject var store: INDChatStore
    let configuration: INDChatConfiguration
    private var isPhone: Bool {
        #if os(iOS)
        UIDevice.current.userInterfaceIdiom == .phone
        #else
        false
        #endif
    }

    var body: some View {
        Group {
            if isPhone || configuration.fullscreen {
                INDChatPanel(store: store, configuration: configuration)
            } else {
                ZStack(alignment: .bottomTrailing) {
                    Color.clear.contentShape(Rectangle()).onTapGesture { store.close() }
                    INDChatPanel(store: store, configuration: configuration)
                        .frame(width: configuration.theme.panelWidth, height: configuration.theme.panelHeight)
                        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                        .shadow(color: .black.opacity(0.22), radius: 22, y: 8)
                        .padding(20)
                }
            }
        }
    }
}

private struct INDChatLauncher: View {
    let theme: INDChatTheme
    let configuration: INDChatConfiguration
    let open: () -> Void

    var body: some View {
        Button(action: open) {
            launcherIcon
                .font(.system(size: 23, weight: .semibold))
                .foregroundStyle(launcherForegroundColor)
                .frame(width: 60, height: 60)
                .background(launcherBackground)
                .clipShape(Circle())
                .shadow(color: .black.opacity(0.25), radius: 9, y: 5)
        }
        .accessibilityLabel(INDChatLocalization.text("chat.open", configuration: configuration))
        .accessibilityHint(INDChatLocalization.text("chat.open.hint", configuration: configuration))
    }

    @ViewBuilder
    private var launcherIcon: some View {
        switch theme.launcherAppearance.icon {
        case let .system(name) where !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty:
            Image(systemName: name)
        case let .asset(name) where !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty:
            Image(name)
                .resizable()
                .scaledToFit()
                .padding(16)
        default:
            Image(systemName: "message.fill")
        }
    }

    private var launcherForegroundColor: Color {
        if let colorHex = theme.launcherAppearance.iconColorHex?.trimmingCharacters(in: .whitespacesAndNewlines),
           !colorHex.isEmpty {
            return Color(hex: colorHex)
        }
        switch theme.visualStyle {
        case .whatsApp:
            #if os(iOS)
            return Theme.Color.white.color
            #else
            return .white
            #endif
        case .plain, .custom:
            return Color(hex: theme.contactBubbleColorHex)
        }
    }

    @ViewBuilder
    private var launcherBackground: some View {
        if let colorHex = theme.launcherAppearance.backgroundColorHex?.trimmingCharacters(in: .whitespacesAndNewlines),
           !colorHex.isEmpty {
            Color(hex: colorHex)
        } else {
            switch theme.visualStyle {
            case .whatsApp:
                #if os(iOS)
                Theme.Gradient.blueBackground.gradient
                #else
                LinearGradient(
                    colors: [Color(hex: "#1858B4"), Color(hex: "#0F356C"), Color(hex: "#1858B4")],
                    startPoint: .top,
                    endPoint: .bottom
                )
                #endif
            case .plain:
                Color(hex: theme.primaryColorHex)
            case let .custom(appearance):
                launcherCustomBackground(appearance.headerBackground)
            }
        }
    }

    @ViewBuilder
    private func launcherCustomBackground(_ background: INDChatHeaderBackground) -> some View {
        switch background {
        case let .solid(colorHex):
            Color(hex: colorHex)
        case let .gradient(gradient) where gradient.colors.count >= 2:
            LinearGradient(
                colors: gradient.colors.map(Color.init(hex:)),
                startPoint: UnitPoint(x: gradient.startPoint.x, y: gradient.startPoint.y),
                endPoint: UnitPoint(x: gradient.endPoint.x, y: gradient.endPoint.y)
            )
        case .gradient:
            Color(hex: theme.primaryColorHex)
        }
    }
}

private struct INDChatWelcomeLabelView: View {
    let welcomeLabel: INDChatWelcomeLabel
    let theme: INDChatTheme
    let configuration: INDChatConfiguration
    let open: () -> Void
    let dismiss: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Button(action: open) {
                Text(welcomeLabel.text)
                    .multilineTextAlignment(.leading)
            }
            .accessibilityLabel(welcomeLabel.text)
            if welcomeLabel.showsDismissButton {
                Button(action: dismiss) {
                    Image(systemName: "xmark")
                        .font(.caption.weight(.bold))
                }
                .accessibilityLabel(INDChatLocalization.text("chat.dismiss", configuration: configuration))
            }
        }
        .foregroundStyle(Color(hex: theme.welcomeLabelTextColorHex ?? theme.textColorHex))
        .padding(12)
        .background(Color(hex: theme.welcomeLabelBackgroundColorHex ?? theme.surfaceColorHex), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .shadow(color: .black.opacity(0.15), radius: 6, y: 3)
    }
}
