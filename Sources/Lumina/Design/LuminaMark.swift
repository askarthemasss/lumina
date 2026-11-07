import SwiftUI

/// The Lumina mark: light passing through a simple vertical structure.
/// It is drawn rather than loaded from an asset so it stays crisp at any size,
/// including the menu bar and empty states.
struct LuminaMark: View {
    var size: CGFloat = 28
    var showBackground: Bool = true

    var body: some View {
        Canvas { context, canvasSize in
            let rect = CGRect(origin: .zero, size: canvasSize)
            let radius = canvasSize.width * 0.235

            if showBackground {
                let background = Path(roundedRect: rect.insetBy(dx: 0.4, dy: 0.4),
                                      cornerRadius: radius, style: .continuous)
                context.fill(background, with: .color(Palette.ink))
                context.stroke(
                    background,
                    with: .color(.white.opacity(0.09)),
                    lineWidth: max(0.5, canvasSize.width * 0.008)
                )
            }

            let inset = canvasSize.width * 0.23
            let contentWidth = canvasSize.width - inset * 2
            let barWidth = contentWidth * 0.17
            let gap = (contentWidth - barWidth * 3) / 2
            let heights: [CGFloat] = [0.42, 0.58, 0.42]
            let colors: [Color] = [Palette.ivory.opacity(0.78), Palette.ivory, Palette.ivory.opacity(0.78)]

            for index in 0..<3 {
                let height = canvasSize.height * heights[index]
                let x = inset + CGFloat(index) * (barWidth + gap)
                let barRect = CGRect(
                    x: x,
                    y: (canvasSize.height - height) / 2,
                    width: barWidth,
                    height: height
                )
                let bar = Path(roundedRect: barRect,
                               cornerRadius: barWidth / 2,
                               style: .continuous)
                context.fill(bar, with: .color(colors[index]))
            }

            // A single warm beam. It reads as light rather than decoration.
            var beam = Path()
            beam.move(to: CGPoint(x: canvasSize.width * 0.29, y: canvasSize.height * 0.76))
            beam.addLine(to: CGPoint(x: canvasSize.width * 0.73, y: canvasSize.height * 0.23))
            context.stroke(
                beam,
                with: .color(Palette.beam.opacity(0.94)),
                style: StrokeStyle(
                    lineWidth: max(1, canvasSize.width * 0.045),
                    lineCap: .round
                )
            )
        }
        .frame(width: size, height: size)
        .accessibilityLabel("Lumina")
    }
}

struct LuminaWordmark: View {
    var compact: Bool = false

    var body: some View {
        HStack(spacing: compact ? 7 : 9) {
            LuminaMark(size: compact ? 24 : 27)
            Text("Lumina")
                .font(.system(size: compact ? 15 : 16, weight: .semibold))
                .tracking(-0.2)
                .foregroundStyle(Palette.label)
        }
    }
}
