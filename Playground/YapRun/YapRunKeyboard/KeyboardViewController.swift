//
//  KeyboardViewController.swift
//  YapRunKeyboard
//
//  Custom keyboard extension that triggers on-device dictation via the main app.
//

import UIKit
import SwiftUI

final class KeyboardViewController: UIInputViewController {

    private var hostingController: UIHostingController<KeyboardView>!

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()

        // Write full-access status to App Group so the main app can read it.
        // hasFullAccess is true when the user has enabled "Allow Full Access" in Settings.
        SharedDataBridge.shared.defaults?.set(
            hasFullAccess,
            forKey: SharedConstants.Keys.keyboardFullAccessGranted
        )
        SharedDataBridge.shared.defaults?.synchronize()

        DarwinNotificationCenter.shared.addObserver(
            name: SharedConstants.DarwinNotifications.transcriptionReady
        ) { [weak self] in
            self?.handleTranscriptionReady()
        }

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
            onRedoTap:         { [weak self] in self?.handleRedo() },
            onNextKeyboard:    { [weak self] in self?.advanceToNextInputMode() },
            onSpace:           { [weak self] in self?.textDocumentProxy.insertText(" ") },
            onReturn:          { [weak self] in self?.textDocumentProxy.insertText("\n") },
            onDelete:          { [weak self] in self?.textDocumentProxy.deleteBackward() },
            onInsertCharacter: { [weak self] char in self?.textDocumentProxy.insertText(char) }
        )

        hostingController = UIHostingController(rootView: keyboardView)
        hostingController.view.backgroundColor = .clear

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

    // MARK: - "Run" Button

    private func handleRunTap() {
        SharedDataBridge.shared.sessionState = "activating"
        guard let url = URL(string: SharedConstants.startFlowURLString) else { return }
        openURL(url)
    }

    // MARK: - Undo / Redo

    private func handleUndo() {
        guard let text = SharedDataBridge.shared.lastInsertedText, !text.isEmpty else { return }
        SharedDataBridge.shared.undoText = text
        SharedDataBridge.shared.lastInsertedText = nil
        batchDelete(count: text.count)
    }

    private func handleRedo() {
        guard let text = SharedDataBridge.shared.undoText, !text.isEmpty else { return }
        textDocumentProxy.insertText(text)
        SharedDataBridge.shared.lastInsertedText = text
        SharedDataBridge.shared.undoText = nil
    }

    /// Delete `count` characters in chunks, yielding to the run loop between
    /// batches so the keyboard UI stays responsive during long deletions.
    private func batchDelete(count: Int, chunkSize: Int = 50) {
        guard count > 0 else { return }
        let toDelete = min(count, chunkSize)
        for _ in 0..<toDelete {
            textDocumentProxy.deleteBackward()
        }
        let remaining = count - toDelete
        if remaining > 0 {
            DispatchQueue.main.async { [weak self] in
                self?.batchDelete(count: remaining, chunkSize: chunkSize)
            }
        }
    }

    // MARK: - Transcription Result

    private func handleTranscriptionReady() {
        guard let text = SharedDataBridge.shared.transcribedText, !text.isEmpty else { return }
        textDocumentProxy.insertText(text)
        SharedDataBridge.shared.lastInsertedText = text
        SharedDataBridge.shared.transcribedText = nil
    }

    // MARK: - URL Opening

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
