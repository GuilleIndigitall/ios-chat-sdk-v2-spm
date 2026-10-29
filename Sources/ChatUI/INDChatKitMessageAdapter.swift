import ChatCore

#if os(iOS)
import AVKit
import IndigitallDesign
import IndigitallModels
import IndigitallUI
import SwiftUI
import UIKit

final class INDChatKitMessageIDMapper {
    private var identifiers: [String: Int] = [:]
    private var nextLocalID = -1

    func id(for message: INDChatMessage) -> Int {
        if let serverID = message.serverId, let value = Int(serverID) {
            identifiers[message.id] = value
            identifiers[serverID] = value
            return value
        }
        return id(for: message.id)
    }

    func id(for identifier: String) -> Int {
        if let value = Int(identifier) { return value }
        if let id = identifiers[identifier] { return id }
        let id = nextLocalID
        nextLocalID -= 1
        identifiers[identifier] = id
        return id
    }
}

enum INDChatKitMessageAdapter {
    static func conversationMessage(
        from message: INDChatMessage,
        applicationID: Int?,
        idMapper: INDChatKitMessageIDMapper
    ) -> ConversationMessage {
        ConversationMessage(
            id: idMapper.id(for: message),
            content: content(from: message.content),
            sendType: sendType(for: message.direction),
            contentType: contentType(for: message.content),
            status: nil,
            quote: quote(from: message.quote, idMapper: idMapper),
            createdAt: message.createdAt,
            applicationId: applicationID,
            fullTemplateData: templateData(from: message.content),
            suppressStatusIndicator: true
        )
    }

    static func localOverride(for message: INDChatMessage, receivedDate: Date, isHighlighted: Bool) -> AnyView? {
        guard case let .multimedia(multimedia) = message.content, multimedia.url.isFileURL else { return nil }
        return AnyView(
            MessageBubbleView(receivedDate: receivedDate, isReceived: message.direction == .business, status: nil, isHighlighted: isHighlighted) {
                INDChatLocalMultimediaView(multimedia: multimedia)
            }
        )
    }

    private static func content(from value: INDChatMessageContent) -> MessageContent {
        switch value {
        case let .text(body):
            MessageContent(body: body)
        case let .multimedia(multimedia):
            MessageContent(multimedia: multimediaContent(from: multimedia))
        case let .template(template):
            MessageContent(body: template.body)
        case let .carousel(templates):
            MessageContent(body: templates.first?.body)
        case let .interactive(interactive):
            MessageContent(body: interactive.body)
        case let .contacts(contacts):
            MessageContent(contacts: contacts.map(contactContent))
        case let .location(location):
            MessageContent(body: location.name ?? location.address, location: Location(latitude: location.latitude, longitude: location.longitude))
        }
    }

    private static func contentType(for value: INDChatMessageContent) -> ContentType {
        switch value {
        case .text: .text
        case .multimedia: .multimedia
        case .template: .template
        case .carousel, .interactive: .text
        case .contacts: .contacts
        case .location: .location
        }
    }

    private static func sendType(for direction: INDChatDirection) -> SendType {
        direction == .business ? .incoming : .outgoing
    }

    private static func quote(from quote: INDChatMessageQuote?, idMapper: INDChatKitMessageIDMapper) -> MessageQuote? {
        guard let quote, let identifier = quote.referencedMessageID else { return nil }
        return MessageQuote(
            messageId: idMapper.id(for: identifier),
            content: MessageQuoteContent(body: quote.content),
            sendType: quote.direction.map(sendType(for:)) ?? .incoming
        )
    }

    private static func multimediaContent(from value: INDChatMultimedia) -> MessageMultimediaContent {
        MessageMultimediaContent(
            multimediaType: MultimediaType(rawValue: value.type.rawValue) ?? .document,
            multimediaUrl: value.url.absoluteString,
            multimediaFilename: value.filename,
            caption: value.caption
        )
    }

    private static func contactContent(from value: INDChatContact) -> ContactContent {
        ContactContent(
            name: ContactName(firstName: value.name, formattedName: value.name),
            phones: value.phones.map(ContactPhone.init(phone:))
        )
    }

    private static func templateData(from content: INDChatMessageContent) -> TemplateData? {
        guard case let .template(template) = content else { return nil }
        return templateData(template)
    }

    private static func templateData(_ template: INDChatTemplate) -> TemplateData {
        var components: [TemplateComponent] = []
        if let multimedia = template.multimedia {
            let format: TemplateFormat
            switch multimedia.type {
            case .image: format = .image
            case .video: format = .video
            case .document, .audio: format = .document
            }
            components.append(TemplateComponent(type: .header, format: format, multimedia: multimediaContent(from: multimedia)))
        } else if let header = template.header {
            components.append(TemplateComponent(type: .header, format: .text, text: header))
        }
        components.append(TemplateComponent(type: .body, text: template.body))
        if let footer = template.footer { components.append(TemplateComponent(type: .footer, text: footer)) }
        let buttons = template.buttons.map(templateButton)
        if !buttons.isEmpty { components.append(TemplateComponent(type: .buttons, buttons: buttons)) }
        return TemplateData(id: template.id, name: template.id, category: "", language: "", status: "", components: components)
    }

    private static func templateButton(from option: INDChatInteractiveOption) -> TemplateButtonType {
        if option.url != nil { return .url(title: option.title) }
        if option.phoneNumber != nil { return .phone(title: option.title) }
        return .quickReply(title: option.title)
    }
}

private struct INDChatLocalMultimediaView: View {
    let multimedia: INDChatMultimedia

    var body: some View {
        switch multimedia.type {
        case .image:
            if let image = UIImage(contentsOfFile: multimedia.url.path) {
                CCImage(image: image)
            } else {
                fileLink
            }
        case .video:
            VideoPlayer(player: AVPlayer(url: multimedia.url))
                .frame(width: 260, height: 180)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        case .audio:
            CCAudio(audioURL: multimedia.url, isReceived: false, profileImageView: Circle()
                .fill(Theme.Color.blue.color)
                .frame(width: 36, height: 36))
        case .document:
            fileLink
        }
    }

    private var fileLink: some View {
        Link(destination: multimedia.url) {
            Label(multimedia.filename ?? multimedia.type.rawValue.capitalized, systemImage: multimedia.type == .audio ? "waveform" : "doc")
                .frame(maxWidth: 260, minHeight: 48, alignment: .leading)
        }
    }
}
#endif
