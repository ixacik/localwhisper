//
//  HotkeyManager.swift
//  LocalASR
//
//  Created on 14/12/2025.
//

import Foundation
import CoreGraphics
import Carbon.HIToolbox

/// Manages global hotkey detection for push-to-talk functionality
/// Uses CGEvent tap to intercept Cmd+Escape key events system-wide
final class HotkeyManager: @unchecked Sendable {
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var isRunning = false
    private var isKeyDown = false

    private let onKeyDown: @Sendable () -> Void
    private let onKeyUp: @Sendable () -> Void

    // Target hotkey: Cmd + Escape (keycode 53)
    private let targetKeyCode: CGKeyCode = 53  // Escape key
    private let targetModifiers: CGEventFlags = .maskCommand

    init(onKeyDown: @escaping @Sendable () -> Void, onKeyUp: @escaping @Sendable () -> Void) {
        self.onKeyDown = onKeyDown
        self.onKeyUp = onKeyUp
    }

    deinit {
        stop()
    }

    /// Start monitoring for the hotkey
    func start() {
        guard !isRunning else { return }

        // Create event tap
        let eventMask: CGEventMask = (1 << CGEventType.keyDown.rawValue) |
                                      (1 << CGEventType.keyUp.rawValue) |
                                      (1 << CGEventType.flagsChanged.rawValue)

        // We need to pass self to the callback, so we use Unmanaged
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: eventMask,
            callback: { proxy, type, event, refcon -> Unmanaged<CGEvent>? in
                guard let refcon = refcon else {
                    return Unmanaged.passRetained(event)
                }

                let manager = Unmanaged<HotkeyManager>.fromOpaque(refcon).takeUnretainedValue()
                return manager.handleEvent(proxy: proxy, type: type, event: event)
            },
            userInfo: selfPtr
        ) else {
            print("Failed to create event tap. Accessibility permission may not be granted.")
            return
        }

        eventTap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)

        if let source = runLoopSource {
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        }

        CGEvent.tapEnable(tap: tap, enable: true)
        isRunning = true

        print("Hotkey manager started - listening for Cmd+Escape")
    }

    /// Stop monitoring for the hotkey
    func stop() {
        guard isRunning else { return }

        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }

        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }

        eventTap = nil
        runLoopSource = nil
        isRunning = false
        isKeyDown = false

        print("Hotkey manager stopped")
    }

    private func handleEvent(
        proxy: CGEventTapProxy,
        type: CGEventType,
        event: CGEvent
    ) -> Unmanaged<CGEvent>? {
        // Handle tap being disabled (e.g., by system timeout)
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap = eventTap {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            return Unmanaged.passRetained(event)
        }

        let keyCode = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))
        let flags = event.flags

        // Check for our target hotkey (Cmd + Escape)
        let isCmdPressed = flags.contains(.maskCommand)
        let isTargetKey = keyCode == targetKeyCode

        // Also check that no other major modifiers are pressed
        let hasOtherModifiers = flags.contains(.maskShift) ||
                                flags.contains(.maskAlternate) ||
                                flags.contains(.maskControl)

        guard isTargetKey && isCmdPressed && !hasOtherModifiers else {
            return Unmanaged.passRetained(event)
        }

        switch type {
        case .keyDown:
            if !isKeyDown {
                isKeyDown = true
                onKeyDown()
            }
            // Consume the event so it doesn't propagate
            return nil

        case .keyUp:
            if isKeyDown {
                isKeyDown = false
                onKeyUp()
            }
            // Consume the event
            return nil

        case .flagsChanged:
            // Handle case where Cmd is released while Escape was held
            if isKeyDown && !isCmdPressed {
                isKeyDown = false
                onKeyUp()
            }
            return Unmanaged.passRetained(event)

        default:
            return Unmanaged.passRetained(event)
        }
    }
}
