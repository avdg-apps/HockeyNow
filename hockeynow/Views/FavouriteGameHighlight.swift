import SwiftUI
struct FavouriteGameHighlight: ViewModifier {
    let isFavourite: Bool
    let color: Color
    var onRight: Bool = false

    func body(content: Content) -> some View {
        if isFavourite {
            content
                .background(color.opacity(0.10))
                .overlay(alignment: onRight ? .topTrailing : .topLeading) {
                    ZStack(alignment: onRight ? .topTrailing : .topLeading) {
                        CornerTriangle(onRight: onRight).fill(color)
                        Image(systemName: "heart.fill")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundColor(.white)
                            .padding(.top, 4)
                            .padding(onRight ? .trailing : .leading, 4)
                    }
                    .frame(width: 26, height: 26)
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(color.opacity(0.6), lineWidth: 1.5)
                }
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        } else {
            content
        }
    }
}

private struct CornerTriangle: Shape {
    let onRight: Bool

    func path(in rect: CGRect) -> Path {
        var path = Path()
        if onRight {
            path.move(to: CGPoint(x: rect.maxX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        } else {
            path.move(to: CGPoint(x: rect.minX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        }
        path.closeSubpath()
        return path
    }
}
