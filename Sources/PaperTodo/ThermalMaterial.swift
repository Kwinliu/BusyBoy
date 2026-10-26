import SwiftUI

/// Small, irregular losses in the thermal coating keep the ink from looking like vector UI text.
struct ThermalText: View {
    let text: String
    var size: CGFloat = 11
    var weight: Font.Weight = .regular

    var body: some View {
        Text(text)
            .font(.system(size: size, weight: weight, design: .monospaced))
            .foregroundStyle(Color(hex: 0x272B29))
            .mask {
                Rectangle().fill(.white)
                    .overlay {
                        Canvas { context, bounds in
                            var holes = Path()
                            for index in 0..<Int(bounds.width * bounds.height / 22) {
                                var value = UInt64(index + text.utf16.count * 97) &+ 0x9E3779B97F4A7C15
                                value = (value ^ (value >> 30)) &* 0xBF58476D1CE4E5B9
                                value = (value ^ (value >> 27)) &* 0x94D049BB133111EB
                                value ^= value >> 31
                                let x = CGFloat(value & 0xFFFF) / 65535 * bounds.width
                                let y = CGFloat((value >> 16) & 0xFFFF) / 65535 * bounds.height
                                holes.addRect(CGRect(x: x, y: y, width: index % 3 == 0 ? 1 : 0.45, height: index % 5 == 0 ? 0.5 : 0.3))
                            }
                            context.fill(holes, with: .color(.black.opacity(0.62)))
                            for line in 0..<Int(bounds.height * 2) {
                                context.fill(Path(CGRect(x: 0, y: CGFloat(line) * 0.5, width: bounds.width, height: 0.06)),
                                             with: .color(.black.opacity(0.1)))
                            }
                        }
                        .blendMode(.destinationOut)
                    }
                    .compositingGroup()
            }
    }
}

struct StarDivider: View {
    var body: some View {
        ThermalText(text: String(repeating: "*", count: 36), size: 7)
            .tracking(1.15).opacity(0.58)
            .frame(maxWidth: .infinity).frame(height: 14)
            .accessibilityHidden(true)
    }
}

struct ThermalPaperShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: .zero)
        path.addLine(to: CGPoint(x: rect.width, y: 0))
        path.addLine(to: CGPoint(x: rect.width, y: rect.height - 3))
        let teeth = max(1, Int(rect.width / 4.2))
        let step = rect.width / CGFloat(teeth)
        for index in 0..<teeth {
            let ragged = CGFloat(index % 3) * 0.22
            path.addLine(to: CGPoint(x: rect.width - (CGFloat(index) + 0.5) * step, y: rect.height - ragged))
            path.addLine(to: CGPoint(x: rect.width - CGFloat(index + 1) * step, y: rect.height - 2.8 - ragged))
        }
        path.addLine(to: .zero)
        path.closeSubpath()
        return path
    }
}

/// The product-shaped window mask prevents stray alpha pixels from catching the eye on a dark desktop.
struct PrinterCutout: Shape {
    func path(in rect: CGRect) -> Path {
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * rect.width, y: y * rect.height) }
        var path = Path()
        path.move(to: point(0.19, 0.047))
        path.addLine(to: point(0.81, 0.047))
        path.addCurve(to: point(0.89, 0.075), control1: point(0.855, 0.047), control2: point(0.875, 0.05))
        path.addCurve(to: point(0.975, 0.35), control1: point(0.93, 0.12), control2: point(0.95, 0.23))
        path.addCurve(to: point(0.99, 0.53), control1: point(0.99, 0.43), control2: point(0.99, 0.47))
        path.addLine(to: point(0.99, 0.80))
        path.addCurve(to: point(0.94, 0.95), control1: point(0.99, 0.90), control2: point(0.975, 0.94))
        path.addCurve(to: point(0.85, 0.985), control1: point(0.92, 0.99), control2: point(0.89, 0.99))
        path.addLine(to: point(0.16, 0.985))
        path.addCurve(to: point(0.06, 0.95), control1: point(0.11, 0.99), control2: point(0.08, 0.99))
        path.addCurve(to: point(0.02, 0.80), control1: point(0.025, 0.94), control2: point(0.02, 0.89))
        path.addLine(to: point(0.02, 0.53))
        path.addCurve(to: point(0.035, 0.35), control1: point(0.02, 0.47), control2: point(0.02, 0.43))
        path.addCurve(to: point(0.11, 0.075), control1: point(0.055, 0.23), control2: point(0.075, 0.12))
        path.addCurve(to: point(0.19, 0.047), control1: point(0.125, 0.05), control2: point(0.145, 0.047))
        path.closeSubpath()
        return path
    }
}
