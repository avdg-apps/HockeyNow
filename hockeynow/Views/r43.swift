import SwiftUI
import Combine

struct EllipsisLoadingView: View {
    @State private var activeDotIndex = 0
    private let loadingMessages = ["Sharpening the skates…", "Cutting the ice…", "Taping the sticks…", "Warming up the goalies…"]
    private let timer = Timer.publish(every: 0.2, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "arrow.triangle.2.circlepath").font(.system(size: 28)).foregroundColor(.accentColor)
            Text(loadingMessages[activeDotIndex % loadingMessages.count])
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundColor(.secondary)
            HStack(spacing: 8) {
                ForEach(0..<3, id: \.self) { index in
                    Circle()
                        .frame(width: 8, height: 8)
                        .foregroundColor(.accentColor)
                        .opacity(activeDotIndex == index ? 1 : 0.25)
                        .scaleEffect(activeDotIndex == index ? 1.15 : 0.85)
                }
            }
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .frame(height: 480)
        .onReceive(timer) { _ in
            withAnimation(.easeInOut(duration: 0.2)) { activeDotIndex = (activeDotIndex + 1) % 3 }
        }
    }
}
