import SwiftUI
import AppKit

@main
struct DJViewApp: App {
    var body: some Scene {
        WindowGroup {
            MainView()
                .frame(minWidth: 900, minHeight: 650)
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified)
        .commands {
            SidebarCommands()

            CommandGroup(replacing: .newItem) {
                Button("New Window") {
                    if let url = Bundle.main.executableURL {
                        _ = try? Process.run(url, arguments: [])
                    }
                }
                .keyboardShortcut("n", modifiers: .command)

                Button("New Tab") {
                    if let url = Bundle.main.executableURL {
                        _ = try? Process.run(url, arguments: [])
                    }
                }
                .keyboardShortcut("t", modifiers: .command)

                Divider()

                Button("Open DjVu File...") {
                    NSApp.sendAction(#selector(AppDelegate.openDocumentMenuAction), to: nil, from: nil)
                }
                .keyboardShortcut("o", modifiers: .command)
            }

            CommandGroup(replacing: .appSettings) {
                Button("Settings...") {
                    NSApp.sendAction(#selector(AppDelegate.settingsMenuAction), to: nil, from: nil)
                }
                .keyboardShortcut(",", modifiers: .command)
            }

            CommandMenu("View") {
                Button("Continuous Scroll") {
                    NSApp.sendAction(#selector(AppDelegate.layoutContinuousAction), to: nil, from: nil)
                }
                .keyboardShortcut("1", modifiers: .command)

                Button("Single Page") {
                    NSApp.sendAction(#selector(AppDelegate.layoutSingleAction), to: nil, from: nil)
                }
                .keyboardShortcut("2", modifiers: .command)

                Button("Manga (Dual Page)") {
                    NSApp.sendAction(#selector(AppDelegate.layoutMangaAction), to: nil, from: nil)
                }
                .keyboardShortcut("3", modifiers: .command)

                Divider()

                Button("Zoom In") {
                    NSApp.sendAction(#selector(AppDelegate.zoomInMenuAction), to: nil, from: nil)
                }
                .keyboardShortcut("+", modifiers: .command)

                Button("Zoom Out") {
                    NSApp.sendAction(#selector(AppDelegate.zoomOutMenuAction), to: nil, from: nil)
                }
                .keyboardShortcut("-", modifiers: .command)

                Button("Actual Size") {
                    NSApp.sendAction(#selector(AppDelegate.zoomActualAction), to: nil, from: nil)
                }
                .keyboardShortcut("0", modifiers: .command)
            }

            CommandMenu("Find") {
                Button("Find in Document...") {
                    NSApp.sendAction(#selector(AppDelegate.findMenuAction), to: nil, from: nil)
                }
                .keyboardShortcut("f", modifiers: .command)
            }
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    @objc func openDocumentMenuAction() {}
    @objc func settingsMenuAction() {}
    @objc func zoomInMenuAction() {}
    @objc func zoomOutMenuAction() {}
    @objc func zoomActualAction() {}
    @objc func findMenuAction() {}
    @objc func layoutContinuousAction() {}
    @objc func layoutSingleAction() {}
    @objc func layoutMangaAction() {}
}
