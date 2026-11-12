//
//  WindowControls.swift
//  Audio Vusualizer
//
//  The system close / minimize / zoom buttons, for the custom full-screen header
//  (the window's own title bar is hidden there).
//

import AppKit
import SwiftUI

struct WindowControls: NSViewRepresentable {
    func makeNSView(context: Context) -> ControlsView { ControlsView() }
    func updateNSView(_ nsView: ControlsView, context: Context) {}

    final class ControlsView: NSView {
        private let buttons: [NSButton]

        init() {
            let mask: NSWindow.StyleMask = [.titled, .closable, .miniaturizable, .resizable]
            // Fresh instances of the standard buttons; they act on whatever window they're in.
            buttons = [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton].compactMap {
                NSWindow.standardWindowButton($0, for: mask)
            }
            super.init(frame: .zero)
            var x: CGFloat = 0
            for button in buttons {
                button.setFrameOrigin(NSPoint(x: x, y: 0))
                addSubview(button)
                x += button.frame.width + 9   // same spacing as the title bar's buttons
            }
        }

        required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

        override var intrinsicContentSize: NSSize {
            guard let last = buttons.last else { return .zero }
            return NSSize(width: last.frame.maxX, height: last.frame.height)
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            // Minimizing isn't possible in full screen.
            let full = window?.styleMask.contains(.fullScreen) ?? false
            if buttons.count > 1 { buttons[1].isEnabled = !full }
        }

        // Shows the ×, –, ↔ glyphs on all three buttons together while hovering, like the system.
        @objc func _mouseInGroup(_ button: NSButton) -> Bool { mouseInside }
        private var mouseInside = false {
            didSet { buttons.forEach { $0.needsDisplay = true } }
        }
        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            trackingAreas.forEach(removeTrackingArea)
            addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways],
                                           owner: self))
        }
        override func mouseEntered(with event: NSEvent) { mouseInside = true }
        override func mouseExited(with event: NSEvent) { mouseInside = false }
    }
}
