//
//  FullScreenObserver.swift
//  Audio Vusualizer
//
//  Watches the hosting window: whether it's in full screen (including when it's
//  restored straight into full screen at launch, which SwiftUI's own full-screen
//  toolbar handling misses), where the pointer is relative to the window's left
//  edge, and whether a menu is open.
//

import AppKit
import SwiftUI

struct FullScreenObserver: NSViewRepresentable {
    struct Pointer: Equatable {
        /// Distance from the window's left edge, points (negative left of it).
        var fromLeft: CGFloat
        /// The pointer is within the window's vertical extent.
        var insideVertically: Bool
        /// A menu is open.
        var menuOpen: Bool
    }

    @Binding var isFullScreen: Bool
    /// Called ~30 times a second while in full screen.
    var onPointer: (Pointer) -> Void = { _ in }

    func makeNSView(context: Context) -> ObserverView {
        let view = ObserverView()
        updateNSView(view, context: context)
        return view
    }

    func updateNSView(_ nsView: ObserverView, context: Context) {
        nsView.onChange = { value in
            if isFullScreen != value { isFullScreen = value }
        }
        nsView.onPointer = onPointer
    }

    final class ObserverView: NSView {
        var onChange: ((Bool) -> Void)?
        var onPointer: ((Pointer) -> Void)?
        private var tokens: [NSObjectProtocol] = []
        private var timer: Timer?
        private var menuOpen = false

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            stopObserving()
            guard let window else { return }

            let center = NotificationCenter.default
            // "will" notifications so the header hides/shows together with the transition.
            for (name, value) in [(NSWindow.willEnterFullScreenNotification, true),
                                  (NSWindow.didEnterFullScreenNotification, true),
                                  (NSWindow.willExitFullScreenNotification, false),
                                  (NSWindow.didExitFullScreenNotification, false)] {
                tokens.append(center.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated { self?.onChange?(value) }
                })
            }
            for (name, value) in [(NSMenu.didBeginTrackingNotification, true),
                                  (NSMenu.didEndTrackingNotification, false)] {
                tokens.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated { self?.menuOpen = value }
                })
            }

            // Poll the pointer instead of relying on mouse events, which don't reach the
            // window everywhere in full screen (e.g. under the system menu bar).
            let timer = Timer(timeInterval: 1.0 / 30, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.pollPointer() }
            }
            RunLoop.main.add(timer, forMode: .common)  // also while a menu is tracking
            self.timer = timer

            // The window may already be in full screen (restored at launch).
            report(window)
            DispatchQueue.main.async { [weak self, weak window] in
                guard let window else { return }
                self?.report(window)
            }
        }

        private func pollPointer() {
            guard let window, window.styleMask.contains(.fullScreen) else { return }
            let location = NSEvent.mouseLocation  // screen coordinates, origin bottom-left
            let frame = window.frame
            onPointer?(Pointer(fromLeft: location.x - frame.minX,
                               insideVertically: location.y >= frame.minY && location.y <= frame.maxY,
                               menuOpen: menuOpen))
        }


        private func report(_ window: NSWindow) {
            onChange?(window.styleMask.contains(.fullScreen))
        }

        private func stopObserving() {
            tokens.forEach(NotificationCenter.default.removeObserver)
            tokens = []
            timer?.invalidate()
            timer = nil
        }

        deinit {
            MainActor.assumeIsolated { stopObserving() }
        }
    }
}
