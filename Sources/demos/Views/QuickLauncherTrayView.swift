import AppKit
import SwiftUI

struct QuickLauncherTrayView: View {
    @EnvironmentObject private var launcherStore: QuickLauncherStore
    @Environment(\.openSettings) private var openSettings

    private let columns = [
        GridItem(.flexible(), spacing: 6),
        GridItem(.flexible(), spacing: 6),
        GridItem(.flexible(), spacing: 6)
    ]

    var body: some View {
        VStack(spacing: 8) {
            // Header bar
            HStack(spacing: 6) {
                Image(systemName: "bolt.fill")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Color.accentColor)

                Text("QUICK LAUNCHER")
                    .font(.system(size: 10, weight: .heavy, design: .rounded))
                    .foregroundStyle(Color(hex: "9CA3AF"))

                Spacer()

                if let message = launcherStore.lastTriggeredMessage {
                    Text("Sent \(message)")
                        .font(.system(size: 9.5, weight: .medium))
                        .foregroundStyle(Color.green)
                        .transition(.opacity)
                }

                Button {
                    openSettings()
                } label: {
                    Image(systemName: "gearshape")
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(Color(hex: "9CA3AF"))
                }
                .buttonStyle(.plain)
                .help("Configure launcher actions in Settings")

                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        launcherStore.isTrayOpen = false
                    }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(Color(hex: "6B7280"))
                }
                .buttonStyle(.plain)
                .help("Close launcher tray")
            }
            .padding(.horizontal, 4)

            // Action buttons grid (1-9)
            LazyVGrid(columns: columns, spacing: 6) {
                ForEach(launcherStore.items) { item in
                    launcherButton(for: item)
                }
            }
        }
        .padding(10)
        .background {
            RoundedRectangle(cornerRadius: 14)
                .fill(Color(hex: "13161A").opacity(0.96))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(Color.white.opacity(0.12), lineWidth: 1)
                )
                .shadow(color: Color.black.opacity(0.4), radius: 10, x: 0, y: 5)
        }
    }

    private func launcherButton(for item: QuickLauncherItem) -> some View {
        let isTriggered = launcherStore.lastTriggeredId == item.id
        let itemColor: Color = {
            if let hex = item.colorHex {
                return Color(hex: hex)
            }
            return Color.accentColor
        }()

        return Button {
            launcherStore.trigger(item)
        } label: {
            HStack(spacing: 5) {
                // Key Badge
                Text(item.key)
                    .font(.system(size: 10.5, weight: .heavy, design: .monospaced))
                    .foregroundStyle(isTriggered ? Color.black : itemColor)
                    .frame(width: 17, height: 17)
                    .background(
                        isTriggered ? Color.white : itemColor.opacity(0.20),
                        in: RoundedRectangle(cornerRadius: 4)
                    )

                // Title
                Text(item.title)
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(isTriggered ? Color.white : Color(hex: "E5E7EB"))
                    .lineLimit(1)
                    .truncationMode(.tail)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 6)
            .frame(height: 34)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isTriggered ? itemColor.opacity(0.85) : Color.white.opacity(0.06))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(
                        isTriggered ? Color.white : itemColor.opacity(0.35),
                        lineWidth: isTriggered ? 1.5 : 0.8
                    )
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Press \(item.key) in Ableton Live to trigger \(item.title)")
    }
}
