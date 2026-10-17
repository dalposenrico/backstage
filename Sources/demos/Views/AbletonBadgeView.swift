import SwiftUI

/// Authentic Ableton Live icon badge [AL] used in DAWbro and professional audio tools.
struct AbletonBadgeView: View {
    var body: some View {
        Text("AL")
            .font(.system(size: 8.5, weight: .bold, design: .monospaced))
            .foregroundColor(.white)
            .padding(.horizontal, 4)
            .padding(.vertical, 2)
            .background(Color(red: 0.18, green: 0.19, blue: 0.22))
            .clipShape(RoundedRectangle(cornerRadius: 3.5))
            .overlay {
                RoundedRectangle(cornerRadius: 3.5)
                    .stroke(Color.white.opacity(0.18), lineWidth: 0.5)
            }
    }
}
