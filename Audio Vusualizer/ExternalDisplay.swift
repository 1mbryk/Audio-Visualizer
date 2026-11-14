//
//  ExternalDisplay.swift
//  Audio Vusualizer
//
//  Shows the visualizer full screen, without any controls, on another display —
//  an AirPlay display (Control Centre → Screen Mirroring → "Use as Separate Display"),
//  a TV over HDMI, a projector. The controls stay in the main window.
//

import AppKit
import SwiftUI

@Observable
final class ExternalDisplay {
    struct Screen: Identifiable, Hashable {
        let id: CGDirectDisplayID
        let name: String
    }

    /// Displays other than the one the main window is on.
    private(set) var screens: [Screen] = []
    /// The display the user picked; kept while it's disconnected, so the picture
    /// comes back on its own when it reconnects (AirPlay drops out now and then).
    private(set) var target: Screen?
    /// The visualizer is on `target` right now.
    private(set) var isPresenting = false

    @ObservationIgnored private var window: NSWindow?
    @ObservationIgnored private var content: (() -> AnyView)?
    @ObservationIgnored private var token: NSObjectProtocol?
    /// The window holding the controls; its display isn't offered as a target.
    @ObservationIgnored weak var mainWindow: NSWindow? {
        didSet { refresh() }
    }

    init() {
        token = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        refresh()
    }

    /// Starts showing `content` on `screen`.
    func present<Content: View>(on screen: Screen, @ViewBuilder content: @escaping () -> Content) {
        self.content = { AnyView(content()) }
        target = screen
        refresh()
    }

    func stop() {
        target = nil
        content = nil
        closeWindow()
        refresh()
    }

    /// Re-reads the list of displays and puts the window on the target, if it's connected.
    func refresh() {
        let mainScreen = mainWindow?.screen ?? NSScreen.main
        let all = NSScreen.screens.compactMap { screen -> (Screen, NSScreen)? in
            guard let id = screen.displayID else { return nil }
            return (Screen(id: id, name: screen.localizedName), screen)
        }
        screens = all.filter { $0.1 != mainScreen }.map(\.0)

        guard let target, let content,
              let screen = all.first(where: { $0.0.id == target.id })?.1 else {
            closeWindow()
            return
        }
        show(content(), on: screen)
    }

    private func show(_ view: AnyView, on screen: NSScreen) {
        if let window {
            window.setFrame(screen.frame, display: true)
            isPresenting = true
            return
        }
        let window = NSWindow(contentRect: screen.frame, styleMask: .borderless,
                              backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.backgroundColor = .black
        // Above the menu bar of that display; it never takes focus from the controls.
        window.level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 1)
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        window.ignoresMouseEvents = true
        window.hidesOnDeactivate = false
        window.contentView = NSHostingView(rootView: view
            .ignoresSafeArea()
            .background(.black)
            .preferredColorScheme(.dark))
        window.setFrame(screen.frame, display: true)
        window.orderFrontRegardless()
        self.window = window
        isPresenting = true
    }

    private func closeWindow() {
        window?.orderOut(nil)
        window?.contentView = nil
        window = nil
        isPresenting = false
    }
}

private extension NSScreen {
    var displayID: CGDirectDisplayID? {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
    }
}

/// Hands the hosting NSWindow to `onWindow` once the view is in one.
struct WindowReader: NSViewRepresentable {
    var onWindow: (NSWindow?) -> Void

    func makeNSView(context: Context) -> ReaderView {
        let view = ReaderView()
        view.onWindow = onWindow
        return view
    }

    func updateNSView(_ nsView: ReaderView, context: Context) {
        nsView.onWindow = onWindow
    }

    final class ReaderView: NSView {
        var onWindow: ((NSWindow?) -> Void)?
        private var token: NSObjectProtocol?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            onWindow?(window)
            // The list of other displays depends on which one the window is on.
            token.map(NotificationCenter.default.removeObserver)
            token = window.map {
                NotificationCenter.default.addObserver(forName: NSWindow.didChangeScreenNotification,
                                                       object: $0, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated { self?.onWindow?(self?.window) }
                }
            }
        }
    }
}
