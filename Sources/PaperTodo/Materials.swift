import SwiftUI

extension Color {
    init(hex: UInt, opacity: Double = 1) {
        self.init(.sRGB, red: Double((hex >> 16) & 255) / 255, green: Double((hex >> 8) & 255) / 255, blue: Double(hex & 255) / 255, opacity: opacity)
    }
    static let ink = Color(hex: 0x353930)
    static let mutedInk = Color(hex: 0x8E9083)
    static let moss = Color(hex: 0x516C54)
    static let paper = Color(hex: 0xFBFAEF)
}

struct Grain: View {
    var opacity: Double = 0.045
    var body: some View {
        Canvas { context, size in
            // Deterministic fibers stay still while the paper moves.
            for index in 0..<Int(size.width * size.height / 62) {
                var hash = UInt64(index) &+ 0x9E3779B97F4A7C15
                hash = (hash ^ (hash >> 30)) &* 0xBF58476D1CE4E5B9
                hash = (hash ^ (hash >> 27)) &* 0x94D049BB133111EB
                hash ^= hash >> 31
                let x = CGFloat(hash & 0xFFFF) / 65535 * size.width
                let y = CGFloat((hash >> 16) & 0xFFFF) / 65535 * size.height
                let length = CGFloat(index % 3 + 1)
                context.fill(Path(CGRect(x: x, y: y, width: length, height: 0.5)), with: .color(.black.opacity(opacity)))
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

struct ReceiptShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: .zero)
        path.addLine(to: CGPoint(x: rect.width, y: 0))
        path.addLine(to: CGPoint(x: rect.width, y: rect.height - 3))
        let teeth = max(1, Int(rect.width / 5))
        let step = rect.width / CGFloat(teeth)
        for index in 0..<teeth {
            path.addLine(to: CGPoint(x: rect.width - (CGFloat(index) + 0.5) * step, y: rect.height))
            path.addLine(to: CGPoint(x: rect.width - CGFloat(index + 1) * step, y: rect.height - 3))
        }
        path.addLine(to: .zero)
        path.closeSubpath()
        return path
    }
}

struct Perforation: View {
    var body: some View {
        Rectangle()
            .fill(Color.ink.opacity(0.2))
            .frame(height: 1)
            .mask {
                HStack(spacing: 4) {
                    ForEach(0..<90, id: \.self) { _ in Rectangle().frame(width: 3, height: 1) }
                }
            }
            .accessibilityHidden(true)
    }
}

struct TactileButtonStyle: ButtonStyle {
    var primary = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(primary ? Color.white.opacity(0.94) : Color.ink)
            .background {
                RoundedRectangle(cornerRadius: 9)
                    .fill(LinearGradient(colors: primary
                        ? [Color(hex: 0x71866C), Color(hex: 0x50674E)]
                        : [Color(hex: 0xFCFBF4), Color(hex: 0xE8E7DD)], startPoint: .top, endPoint: .bottom))
                    .shadow(color: .black.opacity(configuration.isPressed ? 0.07 : 0.17), radius: configuration.isPressed ? 1 : 2, y: configuration.isPressed ? 0 : 2)
                    .overlay {
                        RoundedRectangle(cornerRadius: 9).strokeBorder(.white.opacity(primary ? 0.18 : 0.8), lineWidth: 1)
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: 9).strokeBorder(.black.opacity(0.14), lineWidth: 0.5)
                    }
            }
            .offset(y: configuration.isPressed ? 1 : 0)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
            .onChange(of: configuration.isPressed) { _, pressed in
                if pressed { Task { @MainActor in ButtonFeedback.play() } }
            }
    }
}

struct KeyCap: View {
    let title: String
    var body: some View {
        Text(title)
            .font(.system(size: 11, weight: .medium, design: .monospaced))
            .foregroundStyle(Color(hex: 0x777C6F))
            .padding(.horizontal, 6).frame(height: 23)
            .background(RoundedRectangle(cornerRadius: 4).fill(Color(hex: 0xF7F6EF))
                .shadow(color: .black.opacity(0.15), radius: 0, y: 1))
            .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Color.black.opacity(0.11), lineWidth: 0.5))
    }
}
