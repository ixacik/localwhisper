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

        panel?.orderFrontRegardless()

        // Animate in
        panel?.alphaValue = 0
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.15
            panel?.animator().alphaValue = 1
        }
    }

    func hide() {
        // Animate out
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.15
            panel?.animator().alphaValue = 0
        } completionHandler: { [weak self] in
            self?.panel?.orderOut(nil)
        }
    }

    private func createPanel() {
        let panel = OverlayPanel()

        let hostingView = NSHostingView(rootView: OverlayView(appState: appState))
        panel.contentView = hostingView

        // Position at bottom center of screen
        if let screen = NSScreen.main {
            let panelWidth: CGFloat = 280
            let panelHeight: CGFloat = 72
            let positionX = (screen.frame.width - panelWidth) / 2
            let positionY: CGFloat = 80  // Distance from bottom

            panel.setFrame(NSRect(x: positionX, y: positionY, width: panelWidth, height: panelHeight), display: true)
        }

        self.panel = panel
    }
}

/// Custom NSPanel for the overlay
final class OverlayPanel: NSPanel {
    override init(
        contentRect: NSRect,
        styleMask style: NSWindow.StyleMask,
        backing backingStoreType: NSWindow.BackingStoreType,
        defer flag: Bool
    ) {
        super.init(
            contentRect: contentRect,
            styleMask: [.nonactivatingPanel, .fullSizeContentView, .borderless],
            backing: .buffered,
            defer: false
        )

        configurePanel()
    }

    convenience init() {
        self.init(
            contentRect: NSRect(x: 0, y: 0, width: 280, height: 72),
            styleMask: [],
            backing: .buffered,
            defer: false
        )
    }

    private func configurePanel() {
        // Panel behavior
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]

        // Appearance
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true

        // Don't show in expose/mission control
        hidesOnDeactivate = false

        // Allow clicks to pass through to other apps
        ignoresMouseEvents = false

        // Vibrancy effect
        let visualEffect = NSVisualEffectView()
        visualEffect.material = .hudWindow
        visualEffect.state = .active
        visualEffect.blendingMode = .behindWindow
        visualEffect.wantsLayer = true
        visualEffect.layer?.cornerRadius = 16
        visualEffect.layer?.masksToBounds = true

        contentView = visualEffect
    }

    // Prevent the panel from becoming key window
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
