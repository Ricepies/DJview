import SwiftUI
import AppKit
import UniformTypeIdentifiers

@main
struct DJViewApp: App {
    var body: some Scene {
        WindowGroup {
            MainView()
        }
        .windowStyle(.automatic)
        .windowToolbarStyle(.unified)
        .commands {
            SidebarCommands()

            CommandGroup(replacing: .newItem) {
                Button("Open...") {
                    let panel = NSOpenPanel()
                    panel.allowedContentTypes = [
                        UTType(filenameExtension: "djvu") ?? .data,
                        UTType(filenameExtension: "djv") ?? .data
                    ]
                    panel.allowsMultipleSelection = false
                    if panel.runModal() == .OK, let url = panel.url {
                        NSApp.sendAction(#selector(AppDelegate.openDocumentURL(_:)), to: nil, from: url)
                    }
                }
                .keyboardShortcut("o", modifiers: .command)
            }
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    @objc func openDocumentURL(_ sender: Any?) {
        // AppKit handle document open
    }
}
