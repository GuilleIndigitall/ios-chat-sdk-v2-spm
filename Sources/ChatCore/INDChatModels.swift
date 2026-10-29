import Foundation

public enum INDChatSocketTransport: String, Codable, Sendable, CaseIterable {
    case websocket
    case polling
}

public enum INDChatConnectionState: String, Codable, Sendable {
    case idle, connecting, authenticating, authenticated, reconnecting, unauthorized, disconnected
}

public enum INDChatMessageStatus: String, Codable, Sendable {
    case pending, sent, delivered, read, error
}

public enum INDChatDirection: String, Codable, Sendable {
    case contact, business
}

public enum INDChatMultimediaType: String, Codable, Sendable, CaseIterable {
    case image, video, audio, document
}

public struct INDChatMultimedia: Equatable, Sendable {
    public let type: INDChatMultimediaType
    public let url: URL
    public let filename: String?
    public let caption: String?
    public let mimeType: String?
    public let multimediaID: Int?

    public init(
        type: INDChatMultimediaType,
        url: URL,
        filename: String? = nil,
        caption: String? = nil,
        mimeType: String? = nil,
        multimediaID: Int? = nil
    ) {
        self.type = type
        self.url = url
        self.filename = filename
        self.caption = caption
        self.mimeType = mimeType
        self.multimediaID = multimediaID
    }
}

public struct INDChatMultimediaUpload: Sendable {
    public let data: Data
    public let type: INDChatMultimediaType
    public let filename: String
    public let mimeType: String
    public let caption: String?

    public init(
        data: Data,
        type: INDChatMultimediaType,
        filename: String,
        mimeType: String,
        caption: String? = nil
    ) {
        self.data = data
        self.type = type
        self.filename = filename
        self.mimeType = mimeType
        self.caption = caption?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
    }
}

public struct INDChatLocation: Equatable, Sendable {
    public let latitude: Double
    public let longitude: Double
    public let name: String?
    public let address: String?

    public init(latitude: Double, longitude: Double, name: String? = nil, address: String? = nil) {
        self.latitude = latitude
        self.longitude = longitude
        self.name = name
        self.address = address
    }
}

public struct INDChatContact: Equatable, Sendable, Identifiable {
    public let name: String
    public let phones: [String]
    public let emails: [String]
    public let addresses: [String]
    public let urls: [URL]

    public var id: String { "\(name)|\(phones.first ?? emails.first ?? urls.first?.absoluteString ?? "")" }

    public init(name: String, phones: [String] = [], emails: [String] = [], addresses: [String] = [], urls: [URL] = []) {
        self.name = name
        self.phones = phones
        self.emails = emails
        self.addresses = addresses
        self.urls = urls
    }
}

public struct INDChatTemplate: Equatable, Sendable, Identifiable {
    public let id: String
    public let header: String?
    public let body: String
    public let footer: String?
    public let multimedia: INDChatMultimedia?
    public let buttons: [INDChatInteractiveOption]

    public init(id: String, header: String? = nil, body: String, footer: String? = nil, multimedia: INDChatMultimedia? = nil, buttons: [INDChatInteractiveOption] = []) {
        self.id = id
        self.header = header
        self.body = body
        self.footer = footer
        self.multimedia = multimedia
        self.buttons = buttons
    }
}

public enum INDChatInteractiveKind: String, Equatable, Sendable {
    case button, list, ctaURL = "ctaUrl", flow, locationRequest, singleProduct, multiProduct
}

public struct INDChatInteractiveOption: Equatable, Sendable, Identifiable {
    public let id: String
    public let title: String
    public let payload: String?
    public let url: URL?
    public let phoneNumber: String?

    public init(id: String, title: String, payload: String? = nil, url: URL? = nil, phoneNumber: String? = nil) {
        self.id = id
        self.title = title
        self.payload = payload
        self.url = url
        self.phoneNumber = phoneNumber
    }
}

public struct INDChatInteractive: Equatable, Sendable {
    public let kind: INDChatInteractiveKind
    public let body: String
    public let options: [INDChatInteractiveOption]

    public init(kind: INDChatInteractiveKind, body: String, options: [INDChatInteractiveOption]) {
        self.kind = kind
        self.body = body
        self.options = options
    }
}

public struct INDChatMessageQuote: Equatable, Sendable {
    public let author: String?
    public let content: String
    public let referencedMessageID: String?
    public let direction: INDChatDirection?

    public init(author: String? = nil, content: String, referencedMessageID: String? = nil, direction: INDChatDirection? = nil) {
        self.author = author
        self.content = content
        self.referencedMessageID = referencedMessageID
        self.direction = direction
    }
}

public struct INDChatButtonClick: Equatable, Sendable {
    public let payload: String
    public let text: String

    public init(payload: String, text: String) {
        self.payload = payload
        self.text = text
    }
}

public enum INDChatMessageContent: Equatable, Sendable {
    case text(String)
    case multimedia(INDChatMultimedia)
    case template(INDChatTemplate)
    case carousel([INDChatTemplate])
    case interactive(INDChatInteractive)
    case contacts([INDChatContact])
    case location(INDChatLocation)

    public var body: String {
        switch self {
        case let .text(value): value
        case let .multimedia(value): value.caption ?? value.filename ?? ""
        case let .template(value): value.body
        case let .carousel(value): value.first?.body ?? ""
        case let .interactive(value): value.body
        case let .contacts(value): value.map(\.name).joined(separator: ", ")
        case let .location(value): value.name ?? value.address ?? "Location"
        }
    }
}

public struct INDChatMessage: Identifiable, Equatable, Sendable {
    public let id: String
    public var serverId: String?
    public var clientMessageId: String?
    public var content: INDChatMessageContent
    public var direction: INDChatDirection
    public var createdAt: Date
    public var status: INDChatMessageStatus
    public var error: String?
    public var quote: INDChatMessageQuote?
    public var buttonClick: INDChatButtonClick?

    public var body: String { content.body }

    public init(
        id: String,
        serverId: String? = nil,
        clientMessageId: String? = nil,
        content: INDChatMessageContent,
        direction: INDChatDirection,
        createdAt: Date,
        status: INDChatMessageStatus,
        error: String? = nil,
        quote: INDChatMessageQuote? = nil,
        buttonClick: INDChatButtonClick? = nil
    ) {
        self.id = id
        self.serverId = serverId
        self.clientMessageId = clientMessageId
        self.content = content
        self.direction = direction
        self.createdAt = createdAt
        self.status = status
        self.error = error
        self.quote = quote
        self.buttonClick = buttonClick
    }
}

public enum INDChatError: LocalizedError, Equatable, Sendable {
    case invalidConfiguration(String)
    case authentication(String?)
    case connection(String?)
    case server(String)

    public var errorDescription: String? {
        switch self {
        case let .invalidConfiguration(reason): "Invalid chat configuration: \(reason)"
        case let .authentication(message): message ?? "The chat could not be authenticated."
        case let .connection(message): message ?? "The chat could not be connected."
        case let .server(message): message
        }
    }
}

public struct INDChatGradient: Sendable, Equatable {
    public let colors: [String]
    public let startPoint: INDChatGradientPoint
    public let endPoint: INDChatGradientPoint

    public init(
        colors: [String],
        startPoint: INDChatGradientPoint = .top,
        endPoint: INDChatGradientPoint = .bottom
    ) {
        self.colors = colors
        self.startPoint = startPoint
        self.endPoint = endPoint
    }
}

public struct INDChatGradientPoint: Sendable, Equatable {
    public let x: Double
    public let y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }

    public static let top = INDChatGradientPoint(x: 0.5, y: 0)
    public static let bottom = INDChatGradientPoint(x: 0.5, y: 1)
    public static let leading = INDChatGradientPoint(x: 0, y: 0.5)
    public static let trailing = INDChatGradientPoint(x: 1, y: 0.5)
}

public enum INDChatHeaderBackground: Sendable, Equatable {
    case solid(colorHex: String)
    case gradient(INDChatGradient)
}

public enum INDChatConversationBackground: Sendable, Equatable {
    case solid(colorHex: String)
    /// The name of a local image asset supplied by the host application.
    case image(assetName: String)
}

public struct INDChatCustomAppearance: Sendable, Equatable {
    public let headerBackground: INDChatHeaderBackground
    public let conversationBackground: INDChatConversationBackground

    public init(
        headerBackground: INDChatHeaderBackground,
        conversationBackground: INDChatConversationBackground
    ) {
        self.headerBackground = headerBackground
        self.conversationBackground = conversationBackground
    }
}

public enum INDChatVisualStyle: Sendable, Equatable {
    /// Chat Kit's gradient header and conversation pattern.
    case whatsApp
    /// Solid header and conversation colors from `INDChatTheme`.
    case plain
    /// Client-provided header and conversation backgrounds.
    case custom(INDChatCustomAppearance)
}

/// The image source displayed by the button that opens the chat.
public enum INDChatLauncherIcon: Sendable, Equatable {
    /// An SF Symbol name, such as `message.fill`.
    case system(name: String)
    /// The name of an image asset supplied by the host application.
    case asset(name: String)
}

/// Optional overrides for the button that opens the chat.
///
/// When colors are omitted, the launcher inherits the header appearance from
/// the selected `INDChatVisualStyle`.
public struct INDChatLauncherAppearance: Sendable, Equatable {
    public var icon: INDChatLauncherIcon
    public var iconColorHex: String?
    public var backgroundColorHex: String?

    public init(
        icon: INDChatLauncherIcon = .system(name: "message.fill"),
        iconColorHex: String? = nil,
        backgroundColorHex: String? = nil
    ) {
        self.icon = icon
        self.iconColorHex = iconColorHex
        self.backgroundColorHex = backgroundColorHex
    }
}

public enum INDChatLauncherPosition: Sendable, Equatable {
    case bottomLeading
    case bottomTrailing
}

public struct INDChatWelcomeLabel: Sendable, Equatable {
    public var text: String
    public var showsDismissButton: Bool

    public init(text: String, showsDismissButton: Bool = true) {
        self.text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        self.showsDismissButton = showsDismissButton
    }
}

public struct INDChatTheme: Sendable, Equatable {
    public var primaryColorHex: String
    public var surfaceColorHex: String
    public var backgroundColorHex: String
    public var contactBubbleColorHex: String
    public var businessBubbleColorHex: String
    public var textColorHex: String
    public var mutedTextColorHex: String
    public var errorColorHex: String
    public var panelWidth: Double
    public var panelHeight: Double
    public var visualStyle: INDChatVisualStyle
    public var launcherAppearance: INDChatLauncherAppearance
    public var welcomeLabelBackgroundColorHex: String?
    public var welcomeLabelTextColorHex: String?
    public var scrollToLatestBackgroundColorHex: String?
    public var scrollToLatestTextColorHex: String?

    public init(
        primaryColorHex: String = "#128C7E",
        surfaceColorHex: String = "#FFFFFF",
        backgroundColorHex: String = "#EDE5DD",
        contactBubbleColorHex: String = "#FFFFFF",
        businessBubbleColorHex: String = "#DCF8C6",
        textColorHex: String = "#1F2C34",
        mutedTextColorHex: String = "#667781",
        errorColorHex: String = "#D9534F",
        panelWidth: Double = 390,
        panelHeight: Double = 520,
        visualStyle: INDChatVisualStyle = .whatsApp,
        launcherAppearance: INDChatLauncherAppearance = .init(),
        welcomeLabelBackgroundColorHex: String? = nil,
        welcomeLabelTextColorHex: String? = nil,
        scrollToLatestBackgroundColorHex: String? = nil,
        scrollToLatestTextColorHex: String? = nil
    ) {
        self.primaryColorHex = primaryColorHex
        self.surfaceColorHex = surfaceColorHex
        self.backgroundColorHex = backgroundColorHex
        self.contactBubbleColorHex = contactBubbleColorHex
        self.businessBubbleColorHex = businessBubbleColorHex
        self.textColorHex = textColorHex
        self.mutedTextColorHex = mutedTextColorHex
        self.errorColorHex = errorColorHex
        self.panelWidth = panelWidth
        self.panelHeight = panelHeight
        self.visualStyle = visualStyle
        self.launcherAppearance = launcherAppearance
        self.welcomeLabelBackgroundColorHex = welcomeLabelBackgroundColorHex
        self.welcomeLabelTextColorHex = welcomeLabelTextColorHex
        self.scrollToLatestBackgroundColorHex = scrollToLatestBackgroundColorHex
        self.scrollToLatestTextColorHex = scrollToLatestTextColorHex
    }
}

public struct INDChatLabels: Sendable, Equatable {
    public var title: String
    public var subtitle: String
    public var placeholder: String

    public init(title: String = "Chat", subtitle: String = "Online", placeholder: String = "Type a message") {
        self.title = title
        self.subtitle = subtitle
        self.placeholder = placeholder
    }
}

public struct INDChatConfiguration: Sendable, Equatable {
    public var baseURL: String
    public var channelKey: String
    public var contactCode: String
    public var contactName: String?
    public var initiallyOpen: Bool
    public var fullscreen: Bool
    public var autoOpenDelay: TimeInterval?
    public var launcherPosition: INDChatLauncherPosition
    public var launcherHorizontalOffset: Double
    public var launcherVerticalOffset: Double
    public var welcomeLabel: INDChatWelcomeLabel?
    public var theme: INDChatTheme
    public var labels: INDChatLabels
    public var showEmoji: Bool
    public var localeIdentifier: String?
    public var assignTags: [String]
    public var unassignTags: [String]
    public var logLevel: INDChatLogLevel
    /// Enables local content fixtures only in DEBUG builds. It has no effect in release builds.
    public var debug: Bool

    public init(
        baseURL: String,
        channelKey: String,
        contactCode: String,
        contactName: String? = nil,
        initiallyOpen: Bool = false,
        fullscreen: Bool = false,
        autoOpenDelay: TimeInterval? = nil,
        launcherPosition: INDChatLauncherPosition = .bottomTrailing,
        launcherHorizontalOffset: Double = 20,
        launcherVerticalOffset: Double = 20,
        welcomeLabel: INDChatWelcomeLabel? = nil,
        theme: INDChatTheme = .init(),
        labels: INDChatLabels = .init(),
        showEmoji: Bool = true,
        localeIdentifier: String? = nil,
        assignTags: [String] = [],
        unassignTags: [String] = [],
        logLevel: INDChatLogLevel = .debug,
        debug: Bool = false
    ) {
        self.baseURL = baseURL
        self.channelKey = channelKey
        self.contactCode = contactCode
        self.contactName = contactName?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        self.initiallyOpen = initiallyOpen
        self.fullscreen = fullscreen
        self.autoOpenDelay = autoOpenDelay.flatMap { $0 > 0 ? $0 : nil }
        self.launcherPosition = launcherPosition
        self.launcherHorizontalOffset = max(0, launcherHorizontalOffset)
        self.launcherVerticalOffset = max(0, launcherVerticalOffset)
        self.welcomeLabel = welcomeLabel?.text.nilIfEmpty == nil ? nil : welcomeLabel
        self.theme = theme
        self.labels = labels
        self.showEmoji = showEmoji
        self.localeIdentifier = localeIdentifier?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        self.assignTags = assignTags
        self.unassignTags = unassignTags
        self.logLevel = logLevel
        self.debug = debug
    }

    public func validatedEndpoint() throws -> INDChatEndpoint {
        guard !baseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw INDChatError.invalidConfiguration("baseURL is required")
        }
        guard !channelKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw INDChatError.invalidConfiguration("channelKey is required")
        }
        guard !contactCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw INDChatError.invalidConfiguration("contactCode is required")
        }
        return try INDChatEndpoint(configuration: self)
    }
}

public struct INDChatUIState: Equatable, Sendable {
    public var isOpen: Bool
    public var connection: INDChatConnectionState
    public var messages: [INDChatMessage]
    public var isLoadingOlderMessages: Bool
    public var hasOlderMessages: Bool
    public var applicationId: Int?
    public var isUploadingMultimedia: Bool
    public var error: INDChatError?

    public init(
        isOpen: Bool = false,
        connection: INDChatConnectionState = .idle,
        messages: [INDChatMessage] = [],
        isLoadingOlderMessages: Bool = false,
        hasOlderMessages: Bool = true,
        applicationId: Int? = nil,
        isUploadingMultimedia: Bool = false,
        error: INDChatError? = nil
    ) {
        self.isOpen = isOpen
        self.connection = connection
        self.messages = messages
        self.isLoadingOlderMessages = isLoadingOlderMessages
        self.hasOlderMessages = hasOlderMessages
        self.applicationId = applicationId
        self.isUploadingMultimedia = isUploadingMultimedia
        self.error = error
    }

    public var canSendText: Bool { connection == .authenticated }
}

@MainActor
public protocol INDChatControlling: AnyObject {
    var state: INDChatUIState { get }
    func open()
    func close()
    func toggle()
    @discardableResult func sendText(_ text: String) -> Bool
    @discardableResult func sendMultimedia(_ upload: INDChatMultimediaUpload) -> Bool
    @discardableResult func buttonClicked(payload: String, text: String, quote: INDChatMessageQuote?) -> Bool
    func retryMessage(id: String)
    func requestOlderMessages()
    func clearAllTags()
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
