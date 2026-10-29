#if os(iOS)
import ChatCore
import Combine
import SwiftUI
import UIKit

@MainActor
public final class IndigitallChatViewController: UIViewController {
    public let configuration: INDChatConfiguration
    public var onDidClose: (() -> Void)?

    private let store: INDChatStore
    private let hostingController: UIHostingController<INDChatContent>
    private var stateObservation: AnyCancellable?
    private var fullscreenHostingController: UIHostingController<INDChatPanel>?

    public var state: INDChatUIState { store.state }

    public init(configuration: INDChatConfiguration) {
        self.configuration = configuration
        let store = INDChatStore(configuration: configuration)
        self.store = store
        hostingController = UIHostingController(
            rootView: INDChatContent(
                store: store,
                configuration: configuration,
                showsInlinePresentation: !configuration.fullscreen
            )
        )
        super.init(nibName: nil, bundle: nil)
        observeChatClosure()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = .clear
        view.isOpaque = false
        addChild(hostingController)
        hostingController.view.backgroundColor = .clear
        hostingController.view.isOpaque = false
        hostingController.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(hostingController.view)
        NSLayoutConstraint.activate([
            hostingController.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            hostingController.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            hostingController.view.topAnchor.constraint(equalTo: view.topAnchor),
            hostingController.view.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        hostingController.didMove(toParent: self)
    }

    public override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        updateFullscreenPresentation(isOpen: store.state.isOpen)
    }

    public func open() {
        store.open()
    }

    public func close() {
        store.close()
    }

    public func toggle() {
        store.toggle()
    }

    private func observeChatClosure() {
        stateObservation = store.$state
            .map(\.isOpen)
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self] isOpen in
                guard let self else { return }
                self.updateFullscreenPresentation(isOpen: isOpen)
                if !isOpen { self.onDidClose?() }
            }
    }

    private func updateFullscreenPresentation(isOpen: Bool) {
        guard configuration.fullscreen else { return }

        if isOpen {
            guard fullscreenHostingController == nil, viewIfLoaded?.window != nil else { return }
            let controller = UIHostingController(
                rootView: INDChatPanel(store: store, configuration: configuration)
            )
            controller.modalPresentationStyle = .fullScreen
            controller.view.backgroundColor = .clear
            fullscreenHostingController = controller
            present(controller, animated: true)
        } else if let controller = fullscreenHostingController {
            fullscreenHostingController = nil
            controller.dismiss(animated: true)
        }
    }
}
#endif
