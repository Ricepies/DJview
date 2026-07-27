import SwiftUI
import AppKit
import UniformTypeIdentifiers

// MARK: - Chrome-style Tab Bar
struct TabBarView: View {
    @ObservedObject var tabManager: TabManager
    let onNewTab: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            // Scrollable tab strip
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 1) {
                    ForEach(tabManager.tabs) { tab in
                        TabItemView(
                            tab: tab,
                            isActive: tab.id == tabManager.activeTabID,
                            canClose: tabManager.tabs.count > 1,
                            onActivate: { tabManager.activeTabID = tab.id },
                            onClose: { withAnimation(.easeInOut(duration: 0.18)) { tabManager.closeTab(id: tab.id) } }
                        )
                    }
                }
                .padding(.horizontal, 4)
                .frame(maxHeight: .infinity)
            }

            // New Tab button
            Button(action: onNewTab) {
                Image(systemName: "plus")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.secondary)
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("New Tab (⌘T)")
            .padding(.trailing, 6)
        }
        .frame(height: 36)
        .background(.bar)
        .overlay(alignment: .bottom) {
            Divider()
        }
    }
}

// MARK: - Single Tab Pill
private struct TabItemView: View {
    @ObservedObject var tab: DocumentTab
    let isActive: Bool
    let canClose: Bool
    let onActivate: () -> Void
    let onClose: () -> Void

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 5) {
            // Doc icon
            Image(systemName: tab.viewModel.engine != nil ? "doc.text" : "doc")
                .font(.system(size: 11))
                .foregroundColor(isActive ? .accentColor : .secondary)

            // Title
            Text(tab.title)
                .font(.system(size: 12, weight: isActive ? .semibold : .regular))
                .foregroundColor(isActive ? .primary : .secondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: 160)

            // Close button (always reserve space, only show on hover or active)
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(.secondary)
                    .frame(width: 16, height: 16)
                    .background(Color.primary.opacity(isHovered ? 0.12 : 0.0), in: Circle())
            }
            .buttonStyle(.plain)
            .opacity((isHovered || isActive) && canClose ? 1 : 0)
            .frame(width: 16, height: 16)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .frame(minWidth: 100, maxWidth: 220, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isActive
                    ? Color(NSColor.controlBackgroundColor)
                    : (isHovered ? Color.primary.opacity(0.06) : Color.clear))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(isActive ? Color.primary.opacity(0.14) : Color.clear, lineWidth: 1)
        )
        .contentShape(Rectangle())
        .onTapGesture(perform: onActivate)
        .onHover { isHovered = $0 }
        .animation(.easeInOut(duration: 0.12), value: isHovered)
        .animation(.easeInOut(duration: 0.12), value: isActive)
    }
}
