import SwiftUI

/// Top studio navigation bar inspired by DAWbro and modern DAWs.
struct DawTopNavBar: View {
    @Binding var selection: WorkspaceSection
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var globalHotkey: GlobalHotkeyManager
    @Environment(\.openSettings) private var openSettings
    @State private var hoveredSection: WorkspaceSection?

    var body: some View {
        HStack(spacing: 14) {
            // App Branding
            Button { openSettings() } label: {
                HStack(spacing: 8) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.accent)
                        Image(systemName: "waveform")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.white)
                    }
                    .frame(width: 24, height: 24)

                    HStack(spacing: 4) {
                        Text("goodvibrations")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(.primaryText)
                        Text("HQ")
                            .font(.system(size: 9, weight: .black, design: .monospaced))
                            .foregroundColor(.accent)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1.5)
                            .background(Color.accent.opacity(0.18), in: RoundedRectangle(cornerRadius: 3))
                    }
                }
            }
            .buttonStyle(.plain)
            .help("goodvibrations HQ Settings (⌘,)")

            // Studio Tabs (DAWbro style, clearly outlined, full-width clickable target)
            HStack(spacing: 6) {
                tabButton(
                    title: "Project library",
                    icon: "line.3.horizontal",
                    section: .library
                )

                tabButton(
                    title: "Focus studio",
                    icon: "sparkles",
                    section: .home
                )

                tabButton(
                    title: "Releases",
                    icon: "shippingbox",
                    section: .releases
                )

                tabButton(
                    title: "Tools",
                    icon: "wrench.and.screwdriver",
                    section: .tools
                )
            }

            Spacer()

            // Quick Hotkey HUD Pill
            HStack(spacing: 5) {
                Text("F1")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundColor(.accent)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 2)
                    .background(Color.accent.opacity(0.14), in: RoundedRectangle(cornerRadius: 3))
                Text("Auto-Export")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.secondaryText)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.sidebarBg.opacity(0.6), in: RoundedRectangle(cornerRadius: 5))
            .help("Press F1 anywhere to trigger Ableton auto-export")

            // Settings button
            Button { openSettings() } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.secondaryText)
                    .frame(width: 26, height: 26)
                    .background(Color.hoverBg, in: Circle())
            }
            .buttonStyle(.plain)
            .help("Open Settings (⌘,)")
        }
        .padding(.horizontal, 14)
        .frame(height: 44)
        .background(Color(red: 0.08, green: 0.085, blue: 0.095))
    }

    private func tabButton(title: String, icon: String, section: WorkspaceSection) -> some View {
        let isSelected = selection == section
        let isHovered = hoveredSection == section

        return Button {
            selection = section
        } label: {
            HStack(spacing: 7) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: isSelected ? .bold : .medium))
                Text(title)
                    .font(.system(size: 12, weight: isSelected ? .semibold : .medium))
            }
            .foregroundColor(isSelected ? .white : (isHovered ? Color(white: 0.95) : Color.secondaryText))
            .padding(.horizontal, 13)
            .frame(height: 30)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(
                        isSelected
                            ? Color(red: 0.17, green: 0.18, blue: 0.22)
                            : (isHovered ? Color(red: 0.13, green: 0.14, blue: 0.16) : Color(red: 0.10, green: 0.105, blue: 0.12))
                    )
            )
            .overlay {
                RoundedRectangle(cornerRadius: 6)
                    .stroke(
                        isSelected
                            ? Color.accent
                            : (isHovered ? Color.white.opacity(0.32) : Color.white.opacity(0.14)),
                        lineWidth: isSelected ? 1.2 : 1.0
                    )
            }
            .contentShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .onHover { isOver in
            hoveredSection = isOver ? section : nil
        }
    }
}
