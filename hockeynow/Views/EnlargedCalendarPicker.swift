import SwiftUI
import AppKit

private struct FullScreenSafeWindowConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        DispatchQueue.main.async { configure(view) }
        return view
    }
    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async { configure(nsView) }
    }
    private func configure(_ view: NSView) {
        guard let window = view.window else { return }
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        window.level = .statusBar
        window.orderFrontRegardless()
    }
}

struct ScrollWheelCatcher: NSViewRepresentable {
    let onSwipe: (_ leftward: Bool) -> Void

    func makeNSView(context: Context) -> CatcherView {
        let view = CatcherView()
        view.onSwipe = onSwipe
        return view
    }
    func updateNSView(_ nsView: CatcherView, context: Context) { nsView.onSwipe = onSwipe }

    class CatcherView: NSView {
        var onSwipe: ((_ leftward: Bool) -> Void)?
        private var accumulatedDeltaX: CGFloat = 0
        private var hasTriggeredThisGesture = false

        override func scrollWheel(with event: NSEvent) {
            if event.phase == .began || (event.phase.isEmpty && event.momentumPhase.isEmpty) {
                accumulatedDeltaX = 0; hasTriggeredThisGesture = false
            }
            accumulatedDeltaX += event.scrollingDeltaX
            if !hasTriggeredThisGesture, abs(accumulatedDeltaX) > 40 {
                hasTriggeredThisGesture = true
                NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
                onSwipe?(accumulatedDeltaX > 0)
            }
            if event.phase == .ended || event.phase == .cancelled {
                accumulatedDeltaX = 0; hasTriggeredThisGesture = false
            }
        }
    }
}

struct EnlargedCalendarPicker: View {
    @Binding var selection: Date
    @State private var displayedMonth: Date

    init(selection: Binding<Date>) {
        self._selection = selection
        self._displayedMonth = State(initialValue: selection.wrappedValue)
    }

    private var calendar: Calendar { Calendar.current }

    private var monthTitle: String {
        let f = DateFormatter(); f.dateFormat = "MMMM yyyy"
        return f.string(from: displayedMonth)
    }

    private var daysInGrid: [Date?] {
        guard let monthInterval = calendar.dateInterval(of: .month, for: displayedMonth) else { return [] }
        let firstWeekday = calendar.component(.weekday, from: monthInterval.start)
        let leadingEmpty = (firstWeekday - calendar.firstWeekday + 7) % 7
        var days: [Date?] = Array(repeating: nil, count: leadingEmpty)
        var current = monthInterval.start
        while current < monthInterval.end {
            days.append(current)
            current = calendar.date(byAdding: .day, value: 1, to: current) ?? monthInterval.end
        }
        return days
    }

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Button(action: { shiftMonth(-1) }) { Image(systemName: "chevron.left").font(.system(size: 11, weight: .bold)) }.buttonStyle(.plain)
                Spacer()
                Text(monthTitle).font(.system(size: 12, weight: .bold, design: .monospaced))
                Spacer()
                Button(action: { shiftMonth(1) }) { Image(systemName: "chevron.right").font(.system(size: 11, weight: .bold)) }.buttonStyle(.plain)
            }

            Button(action: jumpToToday) {
                Text("Today").font(.system(size: 9, weight: .bold, design: .monospaced)).foregroundColor(.blue)
            }.buttonStyle(.plain)

            HStack(spacing: 2) {
                ForEach(Array(shortWeekdaySymbols.enumerated()), id: \.offset) { _, symbol in
                    Text(symbol).font(.system(size: 9, weight: .bold, design: .monospaced)).foregroundColor(.secondary).frame(width: 24)
                }
            }

            LazyVGrid(columns: Array(repeating: GridItem(.fixed(24), spacing: 2), count: 7), spacing: 3) {
                ForEach(Array(daysInGrid.enumerated()), id: \.offset) { _, date in
                    if let date {
                        let isSelected = calendar.isDate(date, inSameDayAs: selection)
                        let isToday = calendar.isDateInToday(date)
                        Button(action: { selection = date }) {
                            Text("\(calendar.component(.day, from: date))")
                                .font(.system(size: 10, weight: isSelected ? .bold : .regular, design: .monospaced))
                                .frame(width: 24, height: 24)
                                .background(isSelected ? Color.blue : Color.clear)
                                .foregroundColor(isSelected ? .white : .primary)
                                .overlay(
                                    Circle().stroke(Color.blue, lineWidth: isToday && !isSelected ? 1 : 0)
                                )
                                .cornerRadius(5)
                        }.buttonStyle(.plain)
                    } else {
                        Color.clear.frame(width: 24, height: 24)
                    }
                }
            }
        }
        .padding(8)
        .frame(width: 200)
        .background(ScrollWheelCatcher(onSwipe: { leftward in
            withAnimation(.easeOut(duration: 0.15)) { shiftMonth(leftward ? -1 : 1) }
        }))
        .background(FullScreenSafeWindowConfigurator())
    }

    private var shortWeekdaySymbols: [String] {
        let symbols = calendar.veryShortWeekdaySymbols
        let offset = calendar.firstWeekday - 1
        return Array(symbols[offset...] + symbols[..<offset])
    }

    private func shiftMonth(_ delta: Int) {
        if let newMonth = calendar.date(byAdding: .month, value: delta, to: displayedMonth) {
            displayedMonth = newMonth
        }
    }

    private func jumpToToday() {
        let today = Date()
        withAnimation(.easeOut(duration: 0.15)) { displayedMonth = today }
        selection = today
    }
}
