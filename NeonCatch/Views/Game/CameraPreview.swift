import SwiftUI
import AVFoundation

#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

// MARK: - Camera Preview
// Wraps AVCaptureVideoPreviewLayer in a SwiftUI view for iOS and macOS.

#if os(iOS)
struct CameraPreview: UIViewRepresentable {
    let tracker: CameraHandTracker

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .black
        view.clipsToBounds = true
        if let layer = tracker.previewLayer {
            layer.videoGravity = .resizeAspectFill
            view.layer.addSublayer(layer)
        }
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        guard let layer = tracker.previewLayer else { return }
        if layer.superlayer == nil || layer.superlayer !== uiView.layer {
            layer.removeFromSuperlayer()
            layer.videoGravity = .resizeAspectFill
            uiView.layer.addSublayer(layer)
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.frame = uiView.bounds
        CATransaction.commit()
    }
}

#elseif os(macOS)
struct CameraPreview: NSViewRepresentable {
    let tracker: CameraHandTracker

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        view.wantsLayer = true
        view.layer = CALayer()
        view.layer?.backgroundColor = NSColor.black.cgColor
        view.layer?.masksToBounds = true
        if let layer = tracker.previewLayer {
            layer.videoGravity = .resizeAspectFill
            view.layer?.addSublayer(layer)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        guard let hostLayer = nsView.layer,
              let layer = tracker.previewLayer else { return }
        if layer.superlayer == nil || layer.superlayer !== hostLayer {
            layer.removeFromSuperlayer()
            layer.videoGravity = .resizeAspectFill
            hostLayer.addSublayer(layer)
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.frame = nsView.bounds
        CATransaction.commit()
    }
}
#endif
