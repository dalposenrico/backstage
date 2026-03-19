import SwiftUI
import AppKit

struct ContentView: View {
    @EnvironmentObject var store: AppStore
    @EnvironmentObject var player: AudioPlayer
    @EnvironmentObject var settings: SettingsStore

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                SidebarView()
                    .frame(width: settings.sidebarWidth)

                ResizableDivider(width: $settings.sidebarWidth)

                Group {
                    if let project = store.selectedProject {
                        TrackListView(project: project)
                    } else {
                        EmptyStateView()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider().background(Color.divider)
            PlayerBarView()
        }
        .background(Color.appBg)
        .preferredColorScheme(settings.appearanceMode.colorSchemeOverride)
        .frame(minWidth: 720, minHeight: 480)
    }
}

// MARK: - Resizable divider handle

struct ResizableDivider: View {
    @Binding var width: CGFloat
    @State private var isDragging  = false
    @State private var startWidth: CGFloat = 0
    @State private var isHovered   = false

    var body: some View {
        ZStack {
            Color.divider.frame(width: 1)
            // Extra-wide invisible hit area makes it easy to grab
            Color.clear.frame(width: 10)
        }
        .frame(width: 10)
        .contentShape(Rectangle())
        .onHover { hovered in
            isHovered = hovered
            if hovered { NSCursor.resizeLeftRight.push() }
            else        { NSCursor.pop() }
        }
        .overlay(
            // Subtle highlight while hovering
            Color.accent.opacity(isHovered || isDragging ? 0.35 : 0)
                .frame(width: 1)
                .animation(.easeInOut(duration: 0.15), value: isHovered)
        )
        .gesture(
            DragGesture(minimumDistance: 1, coordinateSpace: .global)
                .onChanged { value in
                    if !isDragging {
                        isDragging = true
                        startWidth = width
                    }
                    width = max(190, min(440, startWidth + value.translation.width))
                }
                .onEnded { _ in isDragging = false }
        )
    }
}
