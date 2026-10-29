import ChatCore
import SwiftUI

#if os(iOS)
import IndigitallModels
import IndigitallUI
import UIKit

struct INDChatKitTimeline: View {
    @ObservedObject var store: INDChatStore
    let theme: INDChatTheme
    let configuration: INDChatConfiguration
    let contact: Contact
    let agent: CCAgent
    @State private var idMapper = INDChatKitMessageIDMapper()
    @State private var scrollToBottomTrigger = 0
    @State private var isAtBottom = true

    var body: some View {
        let sdkMessages = store.state.messages
        let messages = sdkMessages.map {
            INDChatKitMessageAdapter.conversationMessage(
                from: $0,
                applicationID: store.state.applicationId,
                idMapper: idMapper
            )
        }
        let messagesByID = Dictionary(uniqueKeysWithValues: zip(messages.map(\.id), sdkMessages))

        ZStack(alignment: .bottomTrailing) {
            VStack(spacing: 0) {
                if store.state.hasOlderMessages {
                    Button(action: store.requestOlderMessages) {
                        if store.state.isLoadingOlderMessages {
                            Label(INDChatLocalization.text("chat.loadingOlder", configuration: configuration), systemImage: "arrow.clockwise")
                        } else {
                            Text(INDChatLocalization.text("chat.loadOlder", configuration: configuration))
                        }
                    }
                    .disabled(store.state.isLoadingOlderMessages)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Color(hex: theme.primaryColorHex))
                    .padding(.vertical, 8)
                    .accessibilityLabel(INDChatLocalization.text("chat.loadOlder", configuration: configuration))
                }

                MessagesListView(
                    messages: messages,
                    contact: contact,
                    agent: agent,
                    askMoreMessages: store.requestOlderMessages,
                    onQuotedMessageNotFound: store.requestOlderMessages,
                    scrollToBottomTrigger: $scrollToBottomTrigger,
                    isAtBottom: $isAtBottom,
                    messageViewOverride: { message, receivedDate, isHighlighted in
                        guard let sdkMessage = messagesByID[message.id] else { return nil }
                        return messageOverride(for: sdkMessage, receivedDate: receivedDate, isHighlighted: isHighlighted)
                    }
                )
            }

            if !messages.isEmpty && !isAtBottom {
                Button {
                    scrollToBottomTrigger += 1
                } label: {
                    Image(systemName: "arrow.down")
                        .font(.body.weight(.bold))
                        .foregroundStyle(Color(hex: theme.scrollToLatestTextColorHex ?? theme.textColorHex))
                        .frame(width: 42, height: 42)
                        .background(Color(hex: theme.scrollToLatestBackgroundColorHex ?? theme.surfaceColorHex), in: Circle())
                        .shadow(color: .black.opacity(0.18), radius: 5, y: 2)
                }
                .padding(16)
                .accessibilityLabel(INDChatLocalization.text("chat.scrollToLatest", configuration: configuration))
            }
        }
        .onChange(of: sdkMessages.count) { _ in
            guard isAtBottom else { return }
            scrollToBottomTrigger += 1
        }
    }

    private func messageOverride(for message: INDChatMessage, receivedDate: Date, isHighlighted: Bool) -> AnyView? {
        guard requiresWebChatRenderer(message) else { return nil }
        return AnyView(
            INDMessageBubble(
                message: message,
                theme: theme,
                retry: { store.retryMessage(id: message.id) },
                interactiveAction: store.buttonClicked,
                contact: contact,
                agent: agent
            )
        )
    }

    private func requiresWebChatRenderer(_ message: INDChatMessage) -> Bool {
        if message.status == .error { return true }
        return switch message.content {
        case .interactive, .carousel:
            true
        case let .multimedia(multimedia):
            multimedia.url.isFileURL
        default:
            false
        }
    }
}
#endif
