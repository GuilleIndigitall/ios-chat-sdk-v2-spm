import ChatCore
import SwiftUI
#if os(iOS)
import AVKit
import IndigitallDesign
import IndigitallModels
import IndigitallUI
import PhotosUI
import UIKit
import UniformTypeIdentifiers
#endif

struct INDChatPanel: View {
    @ObservedObject var store: INDChatStore
    let configuration: INDChatConfiguration
    @State private var draft = ""
    #if os(iOS)
    @State private var isAttachmentMenuPresented = false
    @State private var isPhotoPickerPresented = false
    @State private var isDocumentPickerPresented = false
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var attachmentError: String?
    #endif

    var body: some View {
        VStack(spacing: 0) {
            header
                .fixedSize(horizontal: false, vertical: true)
            conversation
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    composer
                        .fixedSize(horizontal: false, vertical: true)
                }
        }
        .modifier(INDChatKitThemeModifier(theme: configuration.theme))
        #if os(iOS)
        .confirmationDialog("Attach file", isPresented: $isAttachmentMenuPresented, titleVisibility: .visible) {
            Button("Photo or video") { isPhotoPickerPresented = true }
            Button("File") { isDocumentPickerPresented = true }
        }
        .photosPicker(
            isPresented: $isPhotoPickerPresented,
            selection: $selectedPhoto,
            matching: .any(of: [.images, .videos])
        )
        .fileImporter(
            isPresented: $isDocumentPickerPresented,
            allowedContentTypes: [.audio, .data, .image, .movie, .pdf, .text]
        ) { result in
            importDocument(result)
        }
        .onChange(of: selectedPhoto) { item in
            guard let item else { return }
            importPhoto(item)
        }
        .alert("Unable to attach file", isPresented: Binding(
            get: { attachmentError != nil },
            set: { if !$0 { attachmentError = nil } }
        )) {
            Button("OK", role: .cancel) { attachmentError = nil }
        } message: {
            Text(attachmentError ?? "")
        }
        #endif
    }

    @ViewBuilder
    private var conversation: some View {
        ZStack {
            conversationBackground
            #if os(iOS)
            INDChatKitTimeline(
                store: store,
                theme: configuration.theme,
                configuration: configuration,
                contact: chatKitContact,
                agent: chatKitAgent
            )
            #else
            INDMessageTimeline(store: store, theme: configuration.theme, configuration: configuration)
            #endif
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
    }

    @ViewBuilder
    private var composer: some View {
        #if os(iOS)
        MessageInputView(
            messageText: $draft,
            visibleButtons: [.attachment, .emoji],
            emojiPresentation: .inline,
            onSendTapped: send,
            onMicrophoneTapped: submitRecordedAudio,
            onAttachmentTapped: { isAttachmentMenuPresented = true },
            onTextTemplateTapped: {},
            onAITapped: {}
        )
        .disabled(!store.state.canSendText)
        #else
        INDChatTextInput(
            text: $draft,
            enabled: store.state.canSendText,
            showEmoji: configuration.showEmoji,
            theme: configuration.theme,
            placeholder: configuration.labels.placeholder,
            send: send
        )
        #endif
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.title3)
                .foregroundStyle(headerForegroundColor)
                .frame(width: 38, height: 38)
                .background(headerForegroundColor.opacity(0.18), in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(configuration.labels.title)
                    .font(.headline)
                    .foregroundStyle(headerForegroundColor)
                HStack(spacing: 5) {
                    Circle()
                        .fill(connectionStatusColor)
                        .frame(width: 7, height: 7)
                        .accessibilityHidden(true)
                    Text(connectionText)
                }
                .font(.caption)
                .foregroundStyle(headerForegroundColor.opacity(0.82))
            }
            Spacer()
            Button(action: store.close) {
                Image(systemName: "xmark")
                    .font(.body.weight(.bold))
                    .frame(width: 40, height: 40)
                    .foregroundStyle(headerForegroundColor)
            }
            .accessibilityLabel(INDChatLocalization.text("chat.close", configuration: configuration))
        }
        .padding(.horizontal, 16)
        #if os(iOS)
        .padding(.top, 12)
        #endif
        .padding(.vertical, 12)
        .background(headerBackground)
    }

    private var headerForegroundColor: Color {
        switch configuration.theme.visualStyle {
        case .whatsApp:
            #if os(iOS)
            Theme.Color.white.color
            #else
            .white
            #endif
        case .plain, .custom:
            Color(hex: configuration.theme.contactBubbleColorHex)
        }
    }

    @ViewBuilder
    private var headerBackground: some View {
        switch configuration.theme.visualStyle {
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
            Color(hex: configuration.theme.primaryColorHex)
        case let .custom(appearance):
            customHeaderBackground(appearance.headerBackground)
        }
    }

    @ViewBuilder
    private var conversationBackground: some View {
        switch configuration.theme.visualStyle {
        case .whatsApp:
            #if os(iOS)
            Color(hex: "#F5F1EA")
                .overlay {
                    Image(.conversationBackground)
                        .resizable()
                        .scaledToFill()
                        .foregroundStyle(Theme.Color.gray3.color)
                        .clipped()
                        .allowsHitTesting(false)
                }
            #else
            Color(hex: "#F5F1EA")
            #endif  
        case .plain:
            Color(hex: configuration.theme.backgroundColorHex)
        case let .custom(appearance):
            customConversationBackground(appearance.conversationBackground)
        }
    }

    @ViewBuilder
    private func customHeaderBackground(_ background: INDChatHeaderBackground) -> some View {
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
            Color(hex: configuration.theme.primaryColorHex)
        }
    }

    @ViewBuilder
    private func customConversationBackground(_ background: INDChatConversationBackground) -> some View {
        switch background {
        case let .solid(colorHex):
            Color(hex: colorHex)
        case let .image(assetName) where !assetName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty:
            Image(assetName)
                .resizable()
                .scaledToFill()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
                .background(Color(hex: configuration.theme.backgroundColorHex))
        case .image:
            Color(hex: configuration.theme.backgroundColorHex)
        }
    }

    private var connectionText: String {
        switch store.state.connection {
        case .authenticated: configuration.labels.subtitle
        case .connecting, .authenticating: INDChatLocalization.text("chat.connecting", configuration: configuration)
        case .reconnecting: INDChatLocalization.text("chat.reconnecting", configuration: configuration)
        case .unauthorized:
            store.state.error?.errorDescription ?? INDChatLocalization.text("chat.unauthorized", configuration: configuration)
        case .disconnected:
            store.state.error?.errorDescription ?? INDChatLocalization.text("chat.disconnected", configuration: configuration)
        case .idle: INDChatLocalization.text("chat.disconnected", configuration: configuration)
        }
    }

    private var connectionStatusColor: Color {
        switch store.state.connection {
        case .authenticated: .green
        case .connecting, .authenticating, .reconnecting: .yellow
        case .unauthorized, .disconnected: .red
        case .idle: .gray
        }
    }

    private func send() {
        if store.sendText(draft) { draft = "" }
    }

    #if os(iOS)
    private var chatKitContact: Contact {
        Contact(
            id: 0,
            contactCode: configuration.contactCode,
            applicationId: store.state.applicationId,
            name: configuration.contactName ?? configuration.labels.title,
            channelType: .webchat
        )
    }

    private var chatKitAgent: CCAgent {
        CCAgent(
            id: 0,
            applicationId: store.state.applicationId ?? 0,
            webUserId: 0,
            name: configuration.labels.title
        )
    }

    private func importPhoto(_ item: PhotosPickerItem) {
        Task {
            do {
                guard let data = try await item.loadTransferable(type: Data.self) else {
                    attachmentError = "The selected photo or video could not be read."
                    return
                }
                let contentType = item.supportedContentTypes.first ?? .data
                submitAttachment(data: data, contentType: contentType, filename: nil)
            } catch {
                attachmentError = "The selected photo or video could not be read."
            }
            selectedPhoto = nil
        }
    }

    private func importDocument(_ result: Result<URL, Error>) {
        do {
            let url = try result.get()
            guard url.startAccessingSecurityScopedResource() else {
                attachmentError = "The selected file could not be accessed."
                return
            }
            defer { url.stopAccessingSecurityScopedResource() }
            let contentType = UTType(filenameExtension: url.pathExtension) ?? .data
            submitAttachment(data: try Data(contentsOf: url), contentType: contentType, filename: url.lastPathComponent)
        } catch {
            attachmentError = "The selected file could not be read."
        }
    }

    private func submitRecordedAudio(_ url: URL) {
        defer { try? FileManager.default.removeItem(at: url) }

        do {
            let data = try Data(contentsOf: url)
            let filename = url.lastPathComponent.trimmingCharacters(in: .whitespacesAndNewlines)
            let upload = INDChatMultimediaUpload(
                data: data,
                type: .audio,
                filename: filename.isEmpty ? "audio.m4a" : filename,
                mimeType: "audio/mp4"
            )
            guard store.sendMultimedia(upload) else {
                attachmentError = "The audio exceeds the permitted size or the chat is unavailable."
                return
            }
        } catch {
            attachmentError = "The recorded audio could not be read."
        }
    }

    private func submitAttachment(data: Data, contentType: UTType, filename: String?) {
        let type = multimediaType(for: contentType)
        let generatedFilename = "attachment.\(contentType.preferredFilenameExtension ?? type.fileExtension)"
        let upload = INDChatMultimediaUpload(
            data: data,
            type: type,
            filename: filename?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? generatedFilename,
            mimeType: contentType.preferredMIMEType ?? "application/octet-stream"
        )
        guard store.sendMultimedia(upload) else {
            attachmentError = "The file is unsupported, exceeds the permitted size, or the chat is unavailable."
            return
        }
    }

    private func multimediaType(for contentType: UTType) -> INDChatMultimediaType {
        if contentType.conforms(to: .image) { return .image }
        if contentType.conforms(to: .movie) || contentType.conforms(to: .video) { return .video }
        if contentType.conforms(to: .audio) { return .audio }
        return .document
    }
    #endif
}

#if os(iOS)
private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}

private extension INDChatMultimediaType {
    var fileExtension: String {
        switch self {
        case .image: "jpg"
        case .video: "mp4"
        case .audio: "m4a"
        case .document: "dat"
        }
    }
}
#endif

struct INDMessageTimeline: View {
    @ObservedObject var store: INDChatStore
    let theme: INDChatTheme
    let configuration: INDChatConfiguration
    #if os(iOS)
    let contact: Contact
    let agent: CCAgent
    #endif

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 8) {
                    if store.state.hasOlderMessages {
                        Button(action: store.requestOlderMessages) {
                            if store.state.isLoadingOlderMessages { ProgressView().tint(Color(hex: theme.primaryColorHex)) }
                            else { Text(INDChatLocalization.text("chat.loadOlder", configuration: configuration)) }
                        }
                        .font(.caption.weight(.medium))
                        .foregroundStyle(Color(hex: theme.primaryColorHex))
                        .padding(.vertical, 8)
                        .accessibilityLabel(INDChatLocalization.text("chat.loadOlder", configuration: configuration))
                    }
                    if store.state.messages.isEmpty && store.state.connection == .authenticated {
                        Text(INDChatLocalization.text("chat.empty", configuration: configuration))
                            .font(.subheadline)
                            .foregroundStyle(Color(hex: theme.mutedTextColorHex))
                            .padding(.top, 28)
                    }
                    ForEach(store.state.messages) { message in
                        #if os(iOS)
                        INDMessageBubble(
                            message: message,
                            theme: theme,
                            retry: { store.retryMessage(id: message.id) },
                            interactiveAction: store.buttonClicked,
                            contact: contact,
                            agent: agent
                        )
                        .id(message.id)
                        #else
                        INDMessageBubble(
                            message: message,
                            theme: theme,
                            retry: { store.retryMessage(id: message.id) },
                            interactiveAction: store.buttonClicked
                        )
                        .id(message.id)
                        #endif
                    }
                    Color.clear.frame(height: 1).id("latest")
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
            }
            .onChange(of: store.state.messages.count) { _ in
                withAnimation { proxy.scrollTo("latest", anchor: .bottom) }
            }
        }
    }
}

struct INDMessageBubble: View {
    let message: INDChatMessage
    let theme: INDChatTheme
    let retry: () -> Void
    let interactiveAction: (String, String, INDChatMessageQuote?) -> Bool
    #if os(iOS)
    let contact: Contact
    let agent: CCAgent
    @State private var interactiveList: INDInteractiveListPresentation?
    @State private var contactDetails: INDContactDetailsPresentation?
    #endif

    var body: some View {
        HStack {
            if message.direction == .contact { Spacer(minLength: 52); bubble }
            else { bubble; Spacer(minLength: 52) }
        }
    }

    @ViewBuilder
    private var bubble: some View {
        #if os(iOS)
        VStack(alignment: message.direction == .contact ? .trailing : .leading, spacing: 4) {
            if let quote = message.quote { quotePreview(quote) }
            switch message.content {
            case .text:
                MessageBubbleView(
                    receivedDate: message.createdAt,
                    isReceived: message.direction == .business,
                    status: nil
                ) {
                    Text(message.body)
                        .multilineTextAlignment(.leading)
                }
            case let .multimedia(multimedia):
                MessageBubbleView(
                    receivedDate: message.createdAt,
                    isReceived: message.direction == .business,
                    status: nil
                ) { multimediaContent(multimedia) }
            case let .template(template):
                templateContent(template)
            case let .carousel(templates):
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 10) {
                        ForEach(templates) { template in
                            templateContent(template)
                                .frame(width: 260, alignment: .leading)
                        }
                    }
                }
            case let .interactive(interactive):
                interactiveContent(interactive)
            case let .contacts(contacts):
                MessageBubbleView(receivedDate: message.createdAt, isReceived: message.direction == .business, status: nil) {
                    Button(contacts.count == 1 ? "View contact" : "View contacts") { contactDetails = INDContactDetailsPresentation(contacts: contacts) }
                        .accessibilityLabel(contacts.count == 1 ? "View shared contact" : "View shared contacts")
                }
            case let .location(location):
                MessageBubbleView(receivedDate: message.createdAt, isReceived: message.direction == .business, status: nil) {
                    Link(destination: mapsURL(for: location)) {
                        Label(location.name ?? location.address ?? "Location", systemImage: "mappin.and.ellipse")
                            .frame(maxWidth: 260, minHeight: 48, alignment: .leading)
                    }
                }
            }

            if message.status == .error {
                Button("Retry", action: retry)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color(hex: theme.errorColorHex))
                    .accessibilityLabel("Retry sending")
            }
        }
        .sheet(item: $interactiveList) { presentation in
            INDInteractiveListSheet(interactive: presentation.interactive, quote: message.quote, action: interactiveAction)
                .presentationDetents([.height(presentation.sheetHeight)])
                .presentationDragIndicator(.visible)
        }
        .sheet(item: $contactDetails) { presentation in
            INDContactDetailsSheet(contacts: presentation.contacts)
        }
        #else
        VStack(alignment: .trailing, spacing: 4) {
            if let quote = message.quote { quotePreview(quote) }
            switch message.content {
            case .text:
                Text(message.body)
                    .font(.body)
                    .foregroundStyle(Color(hex: theme.textColorHex))
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: 270, alignment: .leading)
            case let .multimedia(multimedia):
                Link(multimedia.filename ?? multimedia.type.rawValue.capitalized, destination: multimedia.url)
                    .font(.body)
                    .frame(maxWidth: 270, alignment: .leading)
            case let .template(template):
                richTextFallback(header: template.header, body: template.body, footer: template.footer, options: template.buttons)
            case let .carousel(templates):
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack { ForEach(templates) { template in richTextFallback(header: template.header, body: template.body, footer: template.footer, options: template.buttons).frame(width: 250) } }
                }
            case let .interactive(interactive):
                richTextFallback(header: nil, body: interactive.body, footer: nil, options: interactive.options)
            case let .contacts(contacts):
                VStack(alignment: .leading) { ForEach(contacts) { contact in contactText(contact) } }
            case let .location(location):
                Link(location.name ?? location.address ?? "Location", destination: mapsURL(for: location))
            }
            if message.status == .error {
                Button("Retry", action: retry)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color(hex: theme.errorColorHex))
                    .accessibilityLabel("Retry sending")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(
            message.direction == .contact ? Color(hex: theme.businessBubbleColorHex) : Color(hex: theme.contactBubbleColorHex),
            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
        )
        .shadow(color: .black.opacity(0.08), radius: 1, y: 1)
        #endif
    }

    #if os(iOS)
    private func templateContent(_ template: INDChatTemplate) -> some View {
        MessageBubbleView(receivedDate: message.createdAt, isReceived: message.direction == .business, status: nil) {
            VStack(alignment: .leading, spacing: 8) {
                if let multimedia = template.multimedia { multimediaContent(multimedia) }
                if let header = template.header { Text(header).font(.headline) }
                Text(template.body).multilineTextAlignment(.leading)
                if let footer = template.footer { Text(footer).font(.caption).foregroundStyle(.secondary) }
                interactiveOptions(template.buttons)
            }
        }
    }

    @ViewBuilder
    private func interactiveContent(_ interactive: INDChatInteractive) -> some View {
        if interactive.kind == .list {
            MessageBubbleView(
                receivedDate: message.createdAt,
                isReceived: message.direction == .business,
                status: nil,
                buttons: [MessageButtonModel(button: .all(title: "View options")) {
                    interactiveList = INDInteractiveListPresentation(interactive: interactive)
                }]
            ) {
                Text(interactive.body).multilineTextAlignment(.leading)
            }
        } else {
            MessageBubbleView(
                receivedDate: message.createdAt,
                isReceived: message.direction == .business,
                status: nil,
                buttons: messageButtons(for: interactive.options)
            ) {
                Text(interactive.body).multilineTextAlignment(.leading)
            }
        }
    }

    @ViewBuilder
    private func richTextContent(header: String?, body: String, footer: String?, options: [INDChatInteractiveOption]) -> some View {
        MessageBubbleView(receivedDate: message.createdAt, isReceived: message.direction == .business, status: nil) {
            VStack(alignment: .leading, spacing: 8) {
                if let header { Text(header).font(.headline) }
                Text(body).multilineTextAlignment(.leading)
                if let footer { Text(footer).font(.caption).foregroundStyle(.secondary) }
                interactiveOptions(options)
            }
        }
    }

    @ViewBuilder
    private func interactiveOptions(_ options: [INDChatInteractiveOption]) -> some View {
        ForEach(options) { option in
            if let payload = option.payload {
                Button(option.title) { _ = interactiveAction(payload, option.title, message.quote) }
                    .buttonStyle(.bordered)
                    .accessibilityLabel(option.title)
            } else if let url = option.url {
                Link(option.title, destination: url)
            } else if let phone = validatedPhoneURL(option.phoneNumber) {
                Link(option.title, destination: phone)
            } else {
                Text(option.title).foregroundStyle(.secondary)
            }
        }
    }

    private func messageButtons(for options: [INDChatInteractiveOption]) -> [MessageButtonModel] {
        options.map { option in
            MessageButtonModel(button: messageButtonType(for: option)) {
                if let payload = option.payload {
                    _ = interactiveAction(payload, option.title, message.quote)
                } else if let url = option.url {
                    UIApplication.shared.open(url)
                } else if let phone = validatedPhoneURL(option.phoneNumber) {
                    UIApplication.shared.open(phone)
                }
            }
        }
    }

    private func messageButtonType(for option: INDChatInteractiveOption) -> TemplateButtonType {
        if option.url != nil { return .url(title: option.title) }
        if option.phoneNumber != nil { return .phone(title: option.title) }
        return .quickReply(title: option.title)
    }

    @ViewBuilder
    private func multimediaContent(_ multimedia: INDChatMultimedia) -> some View {
        if multimedia.url.isFileURL {
            localMultimediaContent(multimedia)
        } else {
            remoteMultimediaContent(multimedia)
        }
    }

    @ViewBuilder
    private func remoteMultimediaContent(_ multimedia: INDChatMultimedia) -> some View {
        switch multimedia.type {
        case .image:
            CCImage(imageURL: multimedia.url)
        case .video:
            CCVideo(videoURL: multimedia.url)
        case .audio:
            CCAudio(audioURL: multimedia.url, isReceived: message.direction == .business, profileImageView: Circle()
                .fill(Color(hex: theme.primaryColorHex))
                .frame(width: 36, height: 36))
        case .document:
            CCDocument(
                documentURL: multimedia.url,
                documentName: multimedia.filename ?? "Document"
            )
        }
    }

    @ViewBuilder
    private func localMultimediaContent(_ multimedia: INDChatMultimedia) -> some View {
        switch multimedia.type {
        case .image:
            if let image = UIImage(contentsOfFile: multimedia.url.path) {
                CCImage(image: image)
            } else {
                localFileLink(multimedia)
            }
        case .video:
            VideoPlayer(player: AVPlayer(url: multimedia.url))
                .frame(width: 260, height: 180)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        case .audio:
            CCAudio(audioURL: multimedia.url, isReceived: message.direction == .business, profileImageView: Circle()
                .fill(Color(hex: theme.primaryColorHex))
                .frame(width: 36, height: 36))
        case .document:
            localFileLink(multimedia)
        }
    }

    private func localFileLink(_ multimedia: INDChatMultimedia) -> some View {
        Link(destination: multimedia.url) {
            Label(multimedia.filename ?? multimedia.type.rawValue.capitalized, systemImage: multimedia.type == .audio ? "waveform" : "doc")
                .frame(maxWidth: 260, minHeight: 48, alignment: .leading)
        }
    }
    #endif

    @ViewBuilder
    private func richTextFallback(header: String?, body: String, footer: String?, options: [INDChatInteractiveOption]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if let header { Text(header).font(.headline) }
            Text(body)
            if let footer { Text(footer).font(.caption).foregroundStyle(Color(hex: theme.mutedTextColorHex)) }
            ForEach(options) { option in
                if let payload = option.payload {
                    Button(option.title) { _ = interactiveAction(payload, option.title, message.quote) }
                } else if let url = option.url {
                    Link(option.title, destination: url)
                } else { Text(option.title).foregroundStyle(Color(hex: theme.mutedTextColorHex)) }
            }
        }
    }

    private func contactText(_ contact: INDChatContact) -> some View {
        VStack(alignment: .leading) {
            Text(contact.name).font(.headline)
            ForEach(contact.phones, id: \.self) { Text($0) }
            ForEach(contact.emails, id: \.self) { Text($0) }
        }
    }

    private func quotePreview(_ quote: INDChatMessageQuote) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            if let author = quote.author { Text(author).font(.caption.weight(.semibold)) }
            Text(quote.content).font(.caption).lineLimit(2)
        }
        .padding(8)
        .frame(maxWidth: 270, alignment: .leading)
        .background(Color(hex: theme.backgroundColorHex).opacity(0.6), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func mapsURL(for location: INDChatLocation) -> URL {
        URL(string: "https://maps.apple.com/?ll=\(location.latitude),\(location.longitude)")!
    }

    private func validatedPhoneURL(_ phone: String?) -> URL? {
        guard let phone, phone.range(of: "^[+0-9() .-]{3,}$", options: .regularExpression) != nil else { return nil }
        return URL(string: "tel:\(phone.filter { $0.isNumber || $0 == "+" })")
    }
}

#if os(iOS)
private struct INDInteractiveListSheet: View {
    let interactive: INDChatInteractive
    let quote: INDChatMessageQuote?
    let action: (String, String, INDChatMessageQuote?) -> Bool
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List(interactive.options) { option in
                if let payload = option.payload {
                    Button(option.title) {
                        if action(payload, option.title, quote) { dismiss() }
                    }
                } else if let url = option.url {
                    Link(option.title, destination: url)
                } else {
                    Text(option.title).foregroundStyle(.secondary)
                }
            }
            .navigationTitle(interactive.body)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
        }
    }
}

private struct INDInteractiveListPresentation: Identifiable {
    let id = UUID()
    let interactive: INDChatInteractive

    var sheetHeight: CGFloat {
        min(max(180, CGFloat(interactive.options.count) * 52 + 112), 500)
    }
}

private struct INDContactDetailsSheet: View {
    let contacts: [INDChatContact]
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List(contacts) { contact in
                Section(contact.name) {
                    ForEach(contact.phones, id: \.self) { phone in Text(phone) }
                    ForEach(contact.emails, id: \.self) { email in Link(email, destination: URL(string: "mailto:\(email)")!) }
                    ForEach(contact.addresses, id: \.self) { Text($0) }
                    ForEach(contact.urls, id: \.self) { url in Link(url.host ?? url.absoluteString, destination: url) }
                }
            }
            .navigationTitle("Contacts")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
        }
    }
}

private struct INDContactDetailsPresentation: Identifiable {
    let id = UUID()
    let contacts: [INDChatContact]
}
#endif
