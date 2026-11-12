//
//  FullScreenObserver.swift
//  Audio Vusualizer
//
//  Reports whether the hosting window is in full screen — including when the
//  window is restored straight into full screen at launch, which SwiftUI's
//  own full-screen toolbar handling misses.
//

import AppKit
import SwiftUI

struct FullScreenObserver: NSViewRepresentable {
    @Binding var isFullScreen: Bool

    func makeNSView(context: Context) -> ObserverView {
        let view = ObserverView()
        view.onChange = { value in
            if isFullScreen != value { isFullScreen = value }
        }
        return view
    }

    func updateNSView(_ nsView: ObserverView, context: Context) {
        nsView.onChange = { value in
            if isFullScreen != value { isFullScreen = value }
        }
    }

    final class ObserverView: NSView {
        var onChange: ((Bool) -> Void)?
        private var tokens: [NSObjectProtocol] = []

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            tokens.forEach(NotificationCenter.default.removeObserver)
            tokens = []
            guard let window else { return }

            let center = NotificationCenter.default
            // "will" notifications so the header hides/shows together with the transition.
            let names: [(Notification.Name, Bool)] = [
                (NSWindow.willEnterFullScreenNotification, true),
                (NSWindow.didEnterFullScreenNotification, true),
                (NSWindow.willExitFullScreenNotification, false),
                (NSWindow.didExitFullScreenNotification, false),
            ]
            for (name, value) in names {
                tokens.append(center.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated { self?.onChange?(value) }
                })
            }
            // The window may already be in full screen (restored at launch).
            report(window)
            DispatchQueue.main.async { [weak self, weak window] in
                guard let window else { return }
                self?.report(window)
            }
        }

        private func report(_ window: NSWindow) {
            onChange?(window.styleMask.contains(.fullScreen))
        }

        deinit {
            tokens.forEach(NotificationCenter.default.removeObserver)
        }
    }
}
