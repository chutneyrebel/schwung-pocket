import SwiftUI

/// Reusable rotary control. Drag up/right to increase, down/left to decrease.
///
/// The knob is a pure view: it never talks to the network. It reports user-originated changes through
/// `onChange` only while the user is dragging or using VoiceOver adjustments, so values that arrive
/// from outside (e.g. WebSocket updates) update the display without being echoed back.
struct RotaryKnob: View {
    let label: String
    let value: Double
    let range: ClosedRange<Double>
    let step: Double
    let valueText: String
    var tint: Color = Theme.accent
    var onEditingChanged: (Bool) -> Void = { _ in }
    let onChange: (Double) -> Void

    @State private var dragStartValue: Double?
    @State private var dragValue: Double?
    @State private var lastEmitted: Double?

    private let knobSize: CGFloat = 62
    /// Points of drag needed to sweep the full range.
    private let dragSpan: Double = 180
    private let sweep: Double = 0.75 // 270 degrees

    private var span: Double { max(range.upperBound - range.lowerBound, .leastNonzeroMagnitude) }
    private var shownValue: Double { min(max(dragValue ?? value, range.lowerBound), range.upperBound) }
    private var fraction: Double { (shownValue - range.lowerBound) / span }
    private var safeStep: Double { step > 0 ? step : span / 100 }

    var body: some View {
        VStack(spacing: 5) {
            ZStack {
                Circle()
                    .trim(from: 0, to: sweep)
                    .stroke(Theme.surfaceRaised, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                    .rotationEffect(.degrees(135))
                Circle()
                    .trim(from: 0, to: sweep * fraction)
                    .stroke(tint, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                    .rotationEffect(.degrees(135))
                Circle()
                    .fill(Theme.surfaceRaised)
                    .padding(9)
                // Indicator: a short bar from the centre towards the rim, rotated to the value.
                Capsule()
                    .fill(Color.white)
                    .frame(width: 3, height: knobSize * 0.2)
                    .offset(y: -knobSize * 0.2)
                    .rotationEffect(.degrees(-135 + 270 * fraction))
            }
            .frame(width: knobSize, height: knobSize)
            .padding(4) // hit target of 70pt comfortably exceeds the 44pt minimum
            .contentShape(Rectangle())
            .gesture(dragGesture)

            Text(label)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(valueText)
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(tint)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue(valueText)
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: emit(shownValue + safeStep)
            case .decrement: emit(shownValue - safeStep)
            @unknown default: break
            }
        }
        .onChange(of: value) { newValue in
            // External update: only adopt it when the user isn't mid-drag.
            if dragStartValue == nil { lastEmitted = newValue }
        }
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { gesture in
                if dragStartValue == nil {
                    dragStartValue = shownValue
                    onEditingChanged(true)
                }
                guard let start = dragStartValue else { return }
                // Up and right both increase; use whichever axis moved further.
                let travel = Double(-gesture.translation.height + gesture.translation.width * 0.5)
                let proposed = start + (travel / dragSpan) * span
                let snapped = quantize(proposed)
                dragValue = snapped
                emit(snapped)
            }
            .onEnded { _ in
                dragStartValue = nil
                dragValue = nil
                onEditingChanged(false)
            }
    }

    private func emit(_ proposed: Double) {
        let snapped = quantize(proposed)
        guard snapped != lastEmitted else { return }
        lastEmitted = snapped
        onChange(snapped)
    }

    /// Clamps to the range and snaps to the step grid so out-of-range or off-grid values never leave the knob.
    private func quantize(_ proposed: Double) -> Double {
        guard proposed.isFinite else { return range.lowerBound }
        let clamped = min(max(proposed, range.lowerBound), range.upperBound)
        let stepped = range.lowerBound + ((clamped - range.lowerBound) / safeStep).rounded() * safeStep
        let bounded = min(max(stepped, range.lowerBound), range.upperBound)
        return (bounded * 1_000_000).rounded() / 1_000_000
    }
}
