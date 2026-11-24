import SwiftUI

// MARK: - Win Probability
struct InteractiveWinProbabilityChart: View {
    let homeWinOdds: [Double]
    private var odds: [Double] { normalizedWinProbability(homeWinOdds) }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("LIVE WIN PROBABILITY")
                .font(.system(size: 9, weight: .black, design: .monospaced))
                .foregroundColor(.secondary)
            
            GeometryReader { geo in
                ZStack {
                    Path { path in
                        path.move(to: CGPoint(x: 0, y: geo.size.height / 2))
                        path.addLine(to: CGPoint(x: geo.size.width, y: geo.size.height / 2))
                    }
                    .stroke(Color.primary.opacity(0.15), style: StrokeStyle(lineWidth: 1, dash: [4]))
                    
                    if odds.count >= 2 {
                        Path { path in
                            for (index, odd) in odds.enumerated() {
                                let xPosition = geo.size.width * (CGFloat(index) / CGFloat(odds.count - 1))
                                let clampedOdd = max(0.01, min(0.99, odd))
                                let yPosition = geo.size.height * CGFloat(1.0 - clampedOdd)
                                
                                if index == 0 {
                                    path.move(to: CGPoint(x: xPosition, y: yPosition))
                                } else {
                                    path.addLine(to: CGPoint(x: xPosition, y: yPosition))
                                }
                            }
                        }
                        .stroke(LinearGradient(colors: [.blue, .amber, .red], startPoint: .top, endPoint: .bottom), lineWidth: 2)
                    } else {
                        Text("Awaiting timeline vectors...")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(.secondary.opacity(0.6))
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                    }
                }
            }
            .frame(height: 45)
            .background(Color.primary.opacity(0.02))
            .cornerRadius(4)
            
            HStack {
                Text("← Away Dominance").font(.system(size: 8, weight: .medium)).foregroundColor(.secondary)
                Spacer()
                Text("Home Dominance →").font(.system(size: 8, weight: .medium)).foregroundColor(.secondary)
            }
        }
    }
}
