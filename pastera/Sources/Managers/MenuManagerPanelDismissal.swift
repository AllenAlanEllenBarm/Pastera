//
//  MenuManagerPanelDismissal.swift
//
//  Clipy
//  GitHub: https://github.com/clipy
//  HP: https://clipy-app.com
//
//  Created by Codex on 2026/06/08.
//
//  Copyright © 2015-2026 Clipy Project.
//

import Cocoa

extension MenuManager {
    func installPanelDismissMonitorsIfNeeded() {
        if panelDismissLocalMonitor == nil {
            panelDismissLocalMonitor = NSEvent.addLocalMonitorForEvents(
                matching: Self.panelDismissMouseEventMask
            ) { [weak self] event in
                self?.handlePanelDismissMouseDown(at: self?.screenPoint(for: event) ?? NSEvent.mouseLocation)
                return event
            }
        }

        if panelDismissGlobalMonitor == nil {
            panelDismissGlobalMonitor = NSEvent.addGlobalMonitorForEvents(
                matching: Self.panelDismissMouseEventMask
            ) { [weak self] _ in
                let screenPoint = NSEvent.mouseLocation
                DispatchQueue.main.async {
                    self?.handlePanelDismissMouseDown(at: screenPoint)
                }
            }
        }
    }

    func removePanelDismissMonitors() {
        if let monitor = panelDismissLocalMonitor {
            NSEvent.removeMonitor(monitor)
            panelDismissLocalMonitor = nil
        }
        if let monitor = panelDismissGlobalMonitor {
            NSEvent.removeMonitor(monitor)
            panelDismissGlobalMonitor = nil
        }
    }

    func handlePanelDismissMouseDown(at screenPoint: NSPoint) {
        let mainFrame = mainMenuPanelController?.visibleFrame
        let historyFrame = historyPanelController?.visibleFrame
        let snippetFrame = snippetPanelController?.visibleFrame
        guard mainFrame != nil || historyFrame != nil || snippetFrame != nil else {
            removePanelDismissMonitors()
            return
        }

        if isPoint(screenPoint, inside: historyFrame) || isPoint(screenPoint, inside: snippetFrame) {
            return
        }

        historyPanelController?.close()
        snippetPanelController?.close()

        if isPoint(screenPoint, inside: mainFrame) {
            return
        }

        if !isMainMenuPinned {
            mainMenuPanelController?.close()
        }
        removePanelDismissMonitorsIfIdle()
    }

    func removePanelDismissMonitorsIfIdle() {
        guard mainMenuPanelController?.visibleFrame == nil,
              historyPanelController?.visibleFrame == nil,
              snippetPanelController?.visibleFrame == nil else {
            return
        }
        removePanelDismissMonitors()
    }

    func dismissMenuPanelsAfterSelection() {
        historyPanelController?.close()
        snippetPanelController?.close()
        mainMenuPanelController?.close()
        removePanelDismissMonitors()
    }

    func screenPoint(for event: NSEvent) -> NSPoint {
        guard let window = event.window else { return NSEvent.mouseLocation }
        return window.convertPoint(toScreen: event.locationInWindow)
    }

    func isPoint(_ point: NSPoint, inside frame: NSRect?) -> Bool {
        frame?.insetBy(dx: -2, dy: -2).contains(point) == true
    }
}
