//
//  OverlayWindow.swift
//  LocalASR
//
//  Created on 14/12/2025.
//

import AppKit
import SwiftUI

/// Controller for the floating overlay window
@MainActor
final class OverlayWindowController {
    private var panel: OverlayPanel?
    private let appState: AppState

    init(appState: AppState) {
        self.appState = appState
    }

    func show() {
        if panel == nil {
            createPanel()
        }

        panel?.alphaValue = 1
        panel?.orderFrontRegardless()
    }

    func hide() {
        panel?.orderOut(nil)
    }

    private func createPanel() {
        let panel = OverlayPanel()

        let hostingView = NSHostingView(rootView: OverlayView(appState: appState))
        hostingView.layer?.backgroundColor = .clear
        panel.contentView = hostingView

        // Position at bottom center of screen
        if let screen = NSScreen.main {
            // Fixed size: content (50x6) + padding (32x24) = 82x30
            let panelWidth: CGFloat = 82
            let panelHeight: CGFloat = 30
            // Must include screen origin for multi-monitor setups
            let positionX = screen.frame.origin.x + (screen.frame.width - panelWidth) / 2
            let positionY = screen.frame.origin.y + 60  // Distance from bottom

            panel.setFrame(
                NSRect(x: positionX, y: positionY, width: panelWidth, height: panelHeight),
                display: true
            )
        }

        self.panel = panel
    }
}

/// Custom NSPanel for HUD-style overlay
/// Configured to be always on top, click-through, and not recognized as a window
final class OverlayPanel: NSPanel {
    override init(
        contentRect: NSRect,
        styleMask style: NSWindow.StyleMask,
        backing backingStoreType: NSWindow.BackingStoreType,
        defer flag: Bool
    ) {
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        configurePanel()
    }

    convenience init() {
        self.init(
            contentRect: NSRect(x: 0, y: 0, width: 82, height: 30),
            styleMask: [],
            backing: .buffered,
            defer: false
        )
    }

    private func configurePanel() {
        // Window level: above everything including fullscreen apps
        // Using a very high level to ensure it's always visible
        level = .screenSaver

        // Behavior: visible on all spaces, works with fullscreen
        collectionBehavior = [
            .canJoinAllSpaces,
            .fullScreenAuxiliary,
            .stationary,
            .ignoresCycle
        ]

        // Appearance: transparent, no shadow for minimal look
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false

        // Click-through: mouse events pass to underlying windows
        ignoresMouseEvents = true

        // Don't show in Mission Control or app switcher
        hidesOnDeactivate = false

        // Prevent becoming key or main window
        // (handled by overrides below)
    }

    // Never become key window - we're just a HUD
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
