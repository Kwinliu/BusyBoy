import SwiftUI
import AppKit
import CoreText

/// A dry, broad felt-tip mark, laid independently over every wrapped text line.
struct MarkerStrike: View {
    let text: String
    let seed: Int
    var fontSize: CGFloat = 13
    var lineSpacing: CGFloat = 5
    @State private var revealed = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Canvas { context, size in
            let paragraph = NSMutableParagraphStyle()
            paragraph.lineSpacing = lineSpacing
            let attributed = NSAttributedString(string: text, attributes: [
                .font: NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular),
                .paragraphStyle: paragraph
            ])
            let setter = CTFramesetterCreateWithAttributedString(attributed)
            let frame = CTFramesetterCreateFrame(setter, CFRange(), CGPath(rect: CGRect(x: 0, y: 0, width: size.width, height: 10000), transform: nil), nil)
            let lines = CTFrameGetLines(frame) as! [CTLine]
            var origins = [CGPoint](repeating: .zero, count: lines.count)
            CTFrameGetLineOrigins(frame, CFRange(), &origins)
            for (lineIndex, line) in lines.enumerated() {
                let width = min(size.width + 3, CTLineGetTypographicBounds(line, nil, nil, nil) + 5)
                let middle = 10000 - origins[lineIndex].y - 4.5
                guard middle < size.height + 4 else { continue }
                var body = Path()
                for step in 0...26 {
                    let progress = CGFloat(step) / 26
                    let wobble = sin(CGFloat(step * 7 + seed * 3 + lineIndex)) * 0.6
                    let point = CGPoint(x: progress * width - 1, y: middle - 1.65 + wobble - progress * 1.7)
                    if step == 0 { body.move(to: point) } else { body.addLine(to: point) }
                }
                for step in (0...26).reversed() {
                    let progress = CGFloat(step) / 26
                    let wobble = cos(CGFloat(step * 5 + seed * 2 + lineIndex)) * 0.7
                    body.addLine(to: CGPoint(x: progress * width - 1, y: middle + 1.65 + wobble - progress * 1.7))
                }
                body.closeSubpath()
                context.fill(body, with: .color(Color(hex: 0x42473A).opacity(0.48)))
                for strand in 0..<19 {
                    var path = Path()
                    let fiber = CGFloat(strand) / 19 * 5.5 - 2.75
                    let start = CGFloat((strand * 7 + seed) % 6) * 0.55 - 2
                    let end = width - CGFloat((strand * 3 + seed) % 5) * 0.7
                    for step in 0...20 {
                        let progress = CGFloat(step) / 20
                        let x = start + (end - start) * progress
                        let wobble = sin(CGFloat(step) * 1.3 + CGFloat(seed + strand * 2)) * 0.55
                        let y = middle + fiber + wobble - progress * 1.7
                        if step == 0 { path.move(to: CGPoint(x: x, y: y)) }
                        else { path.addLine(to: CGPoint(x: x, y: y)) }
                    }
                    context.stroke(path, with: .color(Color(hex: 0x42473A).opacity(strand % 4 == 0 ? 0.14 : 0.35)),
                                   style: StrokeStyle(lineWidth: strand % 3 == 0 ? 0.55 : 0.34, lineCap: .round, lineJoin: .round))
                }
            }
        }
        .mask(alignment: .leading) {
            Rectangle().scaleEffect(x: revealed ? 1 : 0, y: 1, anchor: .leading)
        }
        .onAppear {
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.28)) { revealed = true }
        }
        .accessibilityHidden(true)
    }
}

