import SwiftUI
import AppKit
import UniformTypeIdentifiers

@main
struct DJViewApp: App {
    @StateObject private var viewModel = AppViewModel()

    var body: some Scene {
        WindowGroup {
            MainView(viewModel: viewModel)
                .onOpenURL { url in
                    viewModel.openDocument(at: url)
                }
        }
        .windowStyle(.automatic)
        .windowToolbarStyle(.unified)
        .commands {
            SidebarCommands()

            CommandGroup(replacing: .newItem) {
                Button("Open...") {
                    let panel = NSOpenPanel()
                    panel.title = "Open DjVu Document"
                    panel.message = "Choose a DjVu file (.djvu, .djv) to read"
                    panel.allowedContentTypes = [
                        UTType(filenameExtension: "djvu") ?? .data,
                        UTType(filenameExtension: "djv") ?? .data
                    ]
                    panel.allowsMultipleSelection = false
                    if panel.runModal() == .OK, let url = panel.url {
                        viewModel.openDocument(at: url)
                    }
                }
                .keyboardShortcut("o", modifiers: .command)
            }
        }
    }
}
