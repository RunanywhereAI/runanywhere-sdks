//
//  KeyboardViewController.swift
//  RunAnywhereKeyboard
//
//  Custom keyboard extension that triggers on-device dictation via the main app.
//
//  State machine:
//    idle        → "Run" tapped → writes sessionState="activating" + opens deep link
//    ready       → mic icon tapped → posts startListening Darwin notification
//    listening   → ✓ tapped → posts stopListening Darwin notification
//    listening   → X tapped → posts cancelListening Darwin notification
//    done        → undo tapped → deletes lastInsertedText characters
//    any         → Darwin transcriptionReady → insert text into proxy
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

        // Observe sessionReady for instant keyboard update (avoids waiting for next 0.3s poll)
        DarwinNotificationCenter.shared.addObserver(
            name: SharedConstants.DarwinNotifications.sessionReady
        ) { /* KeyboardView's 0.3s poll handles the visual update */ }

        setupKeyboardView()
    }

    // MARK: - Setup

    private func setupKeyboardView() {
        let keyboardView = KeyboardView(
            onRunTap:          { [weak self] in self?.handleRunTap() },
            onMicTap:          { DarwinNotificationCenter.shared.post(name: SharedConstants.DarwinNotifications.startListening) },
            onStopTap:         { DarwinNotificationCenter.shared.post(name: SharedConstants.DarwinNotifications.stopListening) },
            onCancelTap:       { DarwinNotificationCenter.shared.post(name: SharedConstants.DarwinNotifications.cancelListening) },
            onUndoTap:         { [weak self] in self?.handleUndo() },
            onNextKeyboard:    { [weak self] in self?.advanceToNextInputMode() },
            onSpace:           { [weak self] in self?.textDocumentProxy.insertText(" ") },
            onReturn:          { [weak self] in self?.textDocumentProxy.insertText("\n") },
            onDelete:          { [weak self] in self?.textDocumentProxy.deleteBackward() },
            onInsertCharacter: { [weak self] char in self?.textDocumentProxy.insertText(char) }
        )

        hostingController = UIHostingController(rootView: keyboardView)
        hostingController.view.backgroundColor = .clear

        // Let the system keyboard height constraint win over SwiftUI's intrinsic size
        hostingController.view.setContentHuggingPriority(.defaultLow, for: .vertical)
        hostingController.view.setContentCompressionResistancePriority(.defaultLow, for: .vertical)

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

    // MARK: - "Run" Button (idle state)

    private func handleRunTap() {
        SharedDataBridge.shared.sessionState = "activating"
        guard let url = URL(string: SharedConstants.startFlowURLString) else { return }
        openURL(url)
    }

    // MARK: - Undo

    private func handleUndo() {
        guard let text = SharedDataBridge.shared.lastInsertedText, !text.isEmpty else { return }
        for _ in text {
            textDocumentProxy.deleteBackward()
        }
        SharedDataBridge.shared.lastInsertedText = nil
    }

    // MARK: - Transcription Result

    private func handleTranscriptionReady() {
        guard let text = SharedDataBridge.shared.transcribedText, !text.isEmpty else { return }
        textDocumentProxy.insertText(text)
        // Do NOT call clearSession() here — that would set state back to "idle".
        // FlowSessionManager handles the done→ready transition itself.
        SharedDataBridge.shared.transcribedText = nil
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
