//
//  VLMCameraPreview.swift
//  RunAnywhereAI
//
//  The live viewfinder, one representable per platform.
//
//  Its own file because it is a UIKit/AppKit bridge rather than part of the
//  workbench's state machine, and because both platforms need a copy: iOS makes
//  the preview layer the view's *backing* layer so UIKit sizes it, and AppKit
//  hosts it as a layer-backed `NSView`.
//

import AVFoundation
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif
#if canImport(AppKit)
import AppKit
#endif

// MARK: - Camera Preview

#if os(iOS)
struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.backgroundColor = .black
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ view: PreviewView, context: Context) {
        // The session can be rebuilt (model swap, retry) while the same view is
        // on screen; without this the preview keeps the dead session and stays
        // black even though frames are flowing.
        if view.previewLayer.session !== session {
            view.previewLayer.session = session
        }
    }

    /// A `UIView` whose backing layer *is* the preview layer, so UIKit sizes it
    /// for us instead of us chasing bounds in `layoutSubviews`.
    class PreviewView: UIView {
        override class var layerClass: AnyClass {
            AVCaptureVideoPreviewLayer.self
        }

        var previewLayer: AVCaptureVideoPreviewLayer {
            layer as! AVCaptureVideoPreviewLayer // swiftlint:disable:this force_cast
        }
    }
}
#elseif os(macOS)
struct CameraPreview: NSViewRepresentable {
    let session: AVCaptureSession

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        let previewLayer = AVCaptureVideoPreviewLayer(session: session)
        previewLayer.videoGravity = .resizeAspectFill
        previewLayer.frame = view.bounds
        previewLayer.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
        view.layer = previewLayer
        view.wantsLayer = true
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        guard let previewLayer = nsView.layer as? AVCaptureVideoPreviewLayer else { return }
        if previewLayer.session !== session {
            previewLayer.session = session
        }
    }
}
#endif
