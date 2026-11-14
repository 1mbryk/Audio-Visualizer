//
//  FrameTimeline.swift
//  Audio Vusualizer
//
//  A per-frame timeline that keeps ticking while a menu is open. SwiftUI's
//  `TimelineView(.animation)` stops delivering frames while the run loop is in
//  menu-tracking mode, so every visualization froze while the mode menu was open.
//  Here frames come from the view's own display link, scheduled in the common
//  run-loop modes; it also follows the refresh rate of the display the view is on.
//

import AppKit
import QuartzCore
import SwiftUI

struct FrameTimelineContext {
    /// Time of the frame being drawn.
    let date: Date
}

struct FrameTimeline<Content: View>: View {
    private let content: (FrameTimelineContext) -> Content
    @State private var clock = FrameClock()

    init(@ViewBuilder content: @escaping (FrameTimelineContext) -> Content) {
        self.content = content
    }

    var body: some View {
        content(FrameTimelineContext(date: clock.date))
            .background(DisplayLinkDriver(clock: clock))
    }
}

@Observable
final class FrameClock {
    var date = Date()
}

private struct DisplayLinkDriver: NSViewRepresentable {
    let clock: FrameClock

    func makeNSView(context: Context) -> LinkView {
        let view = LinkView()
        view.clock = clock
        return view
    }

    func updateNSView(_ nsView: LinkView, context: Context) {
        nsView.clock = clock
    }

    final class LinkView: NSView {
        var clock: FrameClock?
        private var link: CADisplayLink?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            // The link retains its target, so it lives only while the view is in a window.
            link?.invalidate()
            link = nil
            guard window != nil else { return }
            let link = displayLink(target: self, selector: #selector(tick))
            link.add(to: .main, forMode: .common)  // also while a menu is tracking
            self.link = link
        }

        @objc private func tick(_ link: CADisplayLink) {
            clock?.date = Date()
        }
    }
}
