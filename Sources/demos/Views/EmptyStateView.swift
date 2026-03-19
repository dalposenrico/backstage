import SwiftUI

struct EmptyStateView: View {
    @EnvironmentObject var store: AppStore

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "waveform.and.magnifyingglass")
                .font(.system(size: 44))
                .foregroundColor(.tertiaryText)

            VStack(spacing: 6) {
                Text("No folder selected")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.secondaryText)

                Text("Open the folder where your Ableton projects live\nand your exports will appear automatically.")
                    .font(.system(size: 13))
                    .foregroundColor(.tertiaryText)
                    .multilineTextAlignment(.center)
            }

            Button(action: store.selectFolder) {
                Text("Open Music Folder")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.accent)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 9)
                    .background(Color.accent.opacity(0.1))
                    .cornerRadius(8)
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.appBg)
    }
}
