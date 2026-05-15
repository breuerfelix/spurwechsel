//
//  spurwechselApp.swift
//  spurwechsel
//
//  Created by Felix on 23.04.26.
//

import AppKit
import ComposableArchitecture
import GhosttyTerminal
import SwiftUI

final class AppTerminationCoordinator: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        UserDefaults.standard.set(false, forKey: "ApplePressAndHoldEnabled")
        TerminalDebugLog.enable(.all)
        AppLifecycleBridge.shared.applicationDidFinishLaunching()
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        AppLifecycleBridge.shared.open(urls: urls)
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        AppLifecycleBridge.shared.requestTermination { shouldTerminate in
            NSApp.reply(toApplicationShouldTerminate: shouldTerminate)
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}

@main
struct spurwechselApp: App {
    @NSApplicationDelegateAdaptor(AppTerminationCoordinator.self)
    private var terminationCoordinator

    private let composition: AppComposition
    @State private var appStore: StoreOf<AppFeature>

    init() {
        let composition = AppComposition.live(lifecycleBridge: .shared)
        self.composition = composition
        _appStore = State(initialValue: composition.store)
    }

    var body: some Scene {
        Window("Spurwechsel", id: "main") {
            AppView(store: appStore)
                .environment(\.shellSceneBridge, composition.shellSceneBridge)
                .handlesExternalEvents(preferring: ["*"], allowing: ["*"])
        }
        .windowStyle(HiddenTitleBarWindowStyle())
        .defaultSize(width: 1560, height: 940)
        .commands {
            CommandMenu("Spurwechsel") {
                ForEach(SpurwechselCommandMenuSection.allCases, id: \.self) { section in
                    if section != .app {
                        Divider()
                    }

                    ForEach(section.commands, id: \.self) { command in
                        if let shortcut = shortcutBinding(for: command) {
                            Button(command.title) {
                                appStore.send(.shortcut(command))
                            }
                            .keyboardShortcut(
                                shortcut.keyEquivalent,
                                modifiers: shortcut.eventModifiers
                            )
                        } else {
                            Button(command.title) {
                                appStore.send(.shortcut(command))
                            }
                        }
                    }
                }
            }
        }
    }

    private func shortcutBinding(for command: CommandID) -> ResolvedShortcutBinding? {
        appStore.state.shell.resolvedShortcuts.first(where: { $0.command == command })
    }
}

private enum SpurwechselCommandMenuSection: CaseIterable {
    case app
    case project
    case agent
    case view

    var commands: [CommandID] {
        switch self {
        case .app:
            return [
                .toggleCommandBar,
                .quit
            ]
        case .project:
            return [
                .addProject,
                .removeProject,
                .addWorktree,
                .deleteWorktree,
                .selectProject,
                .selectNextProject,
                .selectPreviousProject
            ]
        case .agent:
            return [
                .createAgent,
                .createDefaultAgent,
                .deleteAgent,
                .selectNextAgent,
                .selectPreviousAgent,
                .toggleVoiceInput
            ]
        case .view:
            return [
                .openAgentView,
                .openTerminalView,
                .openVSCodeView,
                .increaseTerminalFontSize,
                .decreaseTerminalFontSize,
                .togglePreviewPane,
                .toggleLeftSidebar,
                .toggleRightSidebar
            ]
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
