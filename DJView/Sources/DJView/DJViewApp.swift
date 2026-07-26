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
                Button("Open DjVu File...") {
                    NSApp.sendAction(#selector(AppDelegate.openDocumentMenuAction), to: nil, from: nil)
                }
                .keyboardShortcut("o", modifiers: .command)
            }

            CommandMenu("View") {
                Button("Zoom In") {
                    NSApp.sendAction(#selector(AppDelegate.zoomInMenuAction), to: nil, from: nil)
                }
                .keyboardShortcut("+", modifiers: .command)

                Button("Zoom Out") {
                    NSApp.sendAction(#selector(AppDelegate.zoomOutMenuAction), to: nil, from: nil)
                }
                .keyboardShortcut("-", modifiers: .command)

                Divider()

                Button("Continuous Scroll") {
                    // Handled by active viewModel
                }
                Button("Single Page") {}
                Button("Manga (Dual Page)") {}
            }
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    @objc func openDocumentMenuAction() {}
    @objc func zoomInMenuAction() {}
    @objc func zoomOutMenuAction() {}
}
