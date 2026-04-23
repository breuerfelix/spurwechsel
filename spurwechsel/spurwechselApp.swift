//
//  spurwechselApp.swift
//  spurwechsel
//
//  Created by Felix on 23.04.26.
//

import AppKit
import GhosttyTerminal
import SwiftUI

final class AppTerminationCoordinator: NSObject, NSApplicationDelegate {
    weak var store: SpurwechselAppStore?
    private var inFlightTerminationTask: Task<Void, Never>?

    func applicationDidFinishLaunching(_ notification: Notification) {
        UserDefaults.standard.set(false, forKey: "ApplePressAndHoldEnabled")
        TerminalDebugLog.enable(.all)
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let store else {
            return .terminateNow
        }

        guard inFlightTerminationTask == nil else {
            return .terminateLater
        }

        inFlightTerminationTask = Task { [weak self, weak store] in
            _ = await store?.prepareForTermination()
            await MainActor.run {
                NSApp.reply(toApplicationShouldTerminate: true)
                self?.inFlightTerminationTask = nil
            }
        }

        return .terminateLater
    }
}

@main
struct spurwechselApp: App {
    @NSApplicationDelegateAdaptor(AppTerminationCoordinator.self)
    private var terminationCoordinator
    @StateObject private var store = SpurwechselAppStore()

    var body: some Scene {
        WindowGroup {
            ContentView(store: store)
                .onAppear {
                    terminationCoordinator.store = store
                }
        }
        .windowStyle(HiddenTitleBarWindowStyle())
        .defaultSize(width: 1560, height: 940)
        .commands {
            CommandMenu("Spurwechsel") {
                let commandBarShortcut = store.commandBarShortcutBinding
                let createDefaultAgentShortcut = store.createDefaultAgentShortcutBinding
                Button("Command Bar") {
                    store.dispatchShortcutAction(.toggleCommandBar)
                }
                .keyboardShortcut(
                    commandBarShortcut.keyEquivalent,
                    modifiers: commandBarShortcut.eventModifiers
                )

                Button("Create Default Agent") {
                    store.dispatchShortcutAction(.createDefaultAgent)
                }
                .keyboardShortcut(
                    createDefaultAgentShortcut.keyEquivalent,
                    modifiers: createDefaultAgentShortcut.eventModifiers
                )
            }
        }
    }
}

private extension ResolvedShortcutBinding {
    var keyEquivalent: KeyEquivalent {
        KeyEquivalent(Character(key))
    }

    var eventModifiers: EventModifiers {
        var resolvedModifiers: EventModifiers = []

        if modifiers.contains(.command) {
            resolvedModifiers.insert(.command)
        }
        if modifiers.contains(.shift) {
            resolvedModifiers.insert(.shift)
        }
        if modifiers.contains(.option) {
            resolvedModifiers.insert(.option)
        }
        if modifiers.contains(.control) {
            resolvedModifiers.insert(.control)
        }

        return resolvedModifiers
    }
}
