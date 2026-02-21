//
//  KeyboardViewController.swift
//  RunAnywhereKeyboard
//
//  Custom keyboard extension that triggers on-device dictation via the main app.
//  Flow:
//    1. User taps "Dictate" → opens runanywhere://startFlow in main app
//    2. Main app records + transcribes on-device (Sherpa-ONNX)
//    3. Main app posts Darwin notification when done
//    4. This VC receives notification → reads text → inserts into proxy
//

import UIKit
import SwiftUI

final class KeyboardViewController: UIInputViewController {

    private var hostingController: UIHostingController<KeyboardView>!

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()

        // Observe transcription-ready notification from main app
        DarwinNotificationCenter.shared.addObserver(
            name: SharedConstants.DarwinNotifications.transcriptionReady
        ) { [weak self] in
            self?.handleTranscriptionReady()
        }

        setupKeyboardView()
    }

    // MARK: - Setup

    private func setupKeyboardView() {
        let keyboardView = KeyboardView(
            onDictate: { [weak self] in self?.startDictation() },
            onNextKeyboard: { [weak self] in self?.advanceToNextInputMode() },
            onSpace: { [weak self] in self?.textDocumentProxy.insertText(" ") },
            onReturn: { [weak self] in self?.textDocumentProxy.insertText("\n") },
            onDelete: { [weak self] in self?.textDocumentProxy.deleteBackward() }
        )

        hostingController = UIHostingController(rootView: keyboardView)
        hostingController.view.backgroundColor = .clear
        addChild(hostingController)
        view.addSubview(hostingController.view)
        hostingController.didMove(toParent: self)

        hostingController.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            hostingController.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            hostingController.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            hostingController.view.topAnchor.constraint(equalTo: view.topAnchor),
            hostingController.view.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    // MARK: - Dictation

    private func startDictation() {
        SharedDataBridge.shared.sessionState = "recording"
        guard let url = URL(string: SharedConstants.startFlowURLString) else { return }
        openURL(url)
    }

    // MARK: - Transcription Result

    private func handleTranscriptionReady() {
        guard let text = SharedDataBridge.shared.transcribedText, !text.isEmpty else { return }
        textDocumentProxy.insertText(text)
        SharedDataBridge.shared.clearSession()
    }

    // MARK: - URL Opening (keyboard extension workaround via responder chain)

    private func openURL(_ url: URL) {
        var responder: UIResponder? = self
        while let r = responder {
            if let app = r as? UIApplication {
                app.open(url, options: [:], completionHandler: nil)
                return
            }
            responder = r.next
        }
    }
}
