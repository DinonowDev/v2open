import SwiftUI

struct InfoTip: View {
    var text: String
    @State private var open = false
    var body: some View {
        Button { open.toggle() } label: {
            Image(systemName: "info.circle")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(C.muted)
        }
        .buttonStyle(.plain)
        .popover(isPresented: $open) {
            Mix(text: text, size: 13)
                .padding(12)
                .frame(width: 250, alignment: .leading)
        }
    }
}
