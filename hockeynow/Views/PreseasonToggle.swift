import SwiftUI

struct PreseasonToggle: View {
    @ObservedObject var fetcher: ESPNNHLFetcher

    var body: some View {
        Button {
            fetcher.showPreseasonOnly.toggle()
        } label: {
            Text("PRESEASON")
                .font(.system(size: 9, weight: .black, design: .monospaced))
                .padding(.horizontal, 7)
                .padding(.vertical, 4)
                .background(fetcher.showPreseasonOnly ? Color.amber : Color.primary.opacity(0.07))
                .foregroundColor(fetcher.showPreseasonOnly ? .black : .secondary)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .buttonStyle(.plain)
        .help("Show preseason games only")
    }
}
