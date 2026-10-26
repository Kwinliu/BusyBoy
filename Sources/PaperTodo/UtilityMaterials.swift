import AppKit
import SwiftUI

enum HousingProfile { case standard, soft, capsule, arched, oval }

struct HousingShape: InsettableShape {
    var profile: HousingProfile = .standard
    var insetAmount: CGFloat = 0
    func path(in rect: CGRect) -> Path {
        let bounds = rect.insetBy(dx: insetAmount, dy: insetAmount)
        switch profile {
        case .oval: return Path(ellipseIn: bounds)
        case .standard: return Path(roundedRect: bounds, cornerRadius: max(0, 23 - insetAmount))
        case .soft: return RoundedRectangle(cornerRadius: max(0, 40 - insetAmount), style: .continuous).path(in: bounds)
        case .capsule: return Capsule().path(in: bounds)
        case .arched:
            func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
                CGPoint(x: bounds.minX + x * bounds.width, y: bounds.minY + y * bounds.height)
            }
            var path = Path()
            path.move(to: point(0.12, 0.07))
            path.addCurve(to: point(0.88, 0.07), control1: point(0.34, -0.01), control2: point(0.66, -0.01))
            path.addCurve(to: point(0.98, 0.29), control1: point(0.96, 0.10), control2: point(0.98, 0.18))
            path.addLine(to: point(0.98, 0.71))
            path.addCurve(to: point(0.88, 0.93), control1: point(0.98, 0.82), control2: point(0.96, 0.90))
            path.addCurve(to: point(0.12, 0.93), control1: point(0.66, 1.01), control2: point(0.34, 1.01))
            path.addCurve(to: point(0.02, 0.71), control1: point(0.04, 0.90), control2: point(0.02, 0.82))
            path.addLine(to: point(0.02, 0.29))
            path.addCurve(to: point(0.12, 0.07), control1: point(0.02, 0.18), control2: point(0.04, 0.10))
            path.closeSubpath()
            return path
        }
    }
    func inset(by amount: CGFloat) -> HousingShape {
        var result = self; result.insetAmount += amount; return result
    }
}

struct WhiteHousing: View {
    var profile: HousingProfile = .standard
    var body: some View {
        let outline = HousingShape(profile: profile)
        outline
            .fill(LinearGradient(stops: [
                .init(color: Color(hex: 0xEEF0F2), location: 0),
                .init(color: Color(hex: 0xF7F7F8), location: 0.25),
                .init(color: Color(hex: 0xE9EBEE), location: 0.8),
                .init(color: Color(hex: 0xCED2D6), location: 1)
            ], startPoint: .topLeading, endPoint: .bottomTrailing))
            .overlay(outline.strokeBorder(Color(hex: 0x9EA5AA), lineWidth: 0.65))
            .overlay(outline.strokeBorder(.white.opacity(0.9), lineWidth: 1.4).padding(2))
            .overlay(outline.strokeBorder(Color(hex: 0xAEB5BB).opacity(0.18), lineWidth: 0.6).padding(5))
            .overlay(Grain(opacity: 0.014).clipShape(outline))
    }
}

enum LiftGeometry {
    static let boardWidth: CGFloat = 280
    static let boardHeight: CGFloat = 148
    static let clearance: CGFloat = 14
    static let anchorDepth: CGFloat = 30
    static let peek: CGFloat = 4
    static let stowedHeight = boardHeight
    static let travel = boardHeight + clearance - peek
    static let height = boardHeight + clearance + anchorDepth
    static let canvasHeight = travel + boardHeight
    static let linkLength: CGFloat = 82
    static let attachmentX: CGFloat = 48
    static let attachmentY = boardHeight - 3

    static func boardTop(_ deployment: CGFloat) -> CGFloat {
        travel * (1 - min(1, max(0, deployment)))
    }
    static func joints(deployment: CGFloat, right: Bool) -> [CGPoint] {
        let base = CGPoint(x: attachmentX, y: height)
        let tip = CGPoint(x: attachmentX, y: boardTop(deployment) + attachmentY)
        let dy = tip.y - base.y
        let elbow = CGPoint(x: base.x + sqrt(max(0, linkLength * linkLength - dy * dy / 4)), y: (tip.y + base.y) / 2)
        return [base, elbow, tip].map { CGPoint(x: right ? boardWidth - $0.x : $0.x, y: $0.y) }
    }
}

struct StowedBackboard: View {
    var body: some View {
        WhiteHousing(profile: .soft).frame(width: LiftGeometry.boardWidth, height: LiftGeometry.boardHeight)
            .frame(width: 344, height: LiftGeometry.stowedHeight, alignment: .top)
            .allowsHitTesting(false).accessibilityHidden(true)
    }
}

struct MechanicalAssembly<Content: View>: View {
    var deployment: CGFloat
    var content: Content
    var body: some View {
        ZStack(alignment: .top) {
            MechanicalLift(deployment: deployment)
                .frame(width: LiftGeometry.boardWidth, height: LiftGeometry.height)
            ZStack {
                WhiteHousing(profile: .soft)
                content
            }
            .frame(width: LiftGeometry.boardWidth, height: LiftGeometry.boardHeight)
            .clipShape(HousingShape(profile: .soft))
            .compositingGroup()
            .shadow(color: .black.opacity(0.22), radius: 3, x: 0, y: 3)
            .offset(y: LiftGeometry.boardTop(deployment))
            .allowsHitTesting(deployment >= 0.999)
            .accessibilityHidden(deployment < 0.999)
        }
        .frame(width: 344, height: LiftGeometry.canvasHeight, alignment: .top)
        .clipped()
    }
}

/// Equal-length links keep their hinges attached throughout the full stroke.
struct MechanicalLift: View {
    var deployment: CGFloat
    var body: some View {
        Canvas { context, size in
            let steel = Gradient(stops: [
                .init(color: Color(hex: 0x9CA6AD), location: 0),
                .init(color: Color(hex: 0xE7EBEE), location: 0.09),
                .init(color: .white, location: 0.17),
                .init(color: Color(hex: 0xD7DDE1), location: 0.29),
                .init(color: Color(hex: 0xFCFEFF), location: 0.43),
                .init(color: Color(hex: 0xF5F8FA), location: 0.51),
                .init(color: Color(hex: 0x7D8A94), location: 0.59),
                .init(color: Color(hex: 0x57656F), location: 0.64),
                .init(color: Color(hex: 0xC8D1D7), location: 0.73),
                .init(color: .white, location: 0.87),
                .init(color: Color(hex: 0xAAB5BD), location: 1)
            ])
            for right in [false, true] {
                let points = LiftGeometry.joints(deployment: deployment, right: right)
                for pair in 0..<2 {
                    var path = Path(); path.move(to: points[pair]); path.addLine(to: points[pair + 1])
                    let a = points[pair], b = points[pair + 1]
                    let length = hypot(b.x - a.x, b.y - a.y)
                    let normal = CGPoint(x: -(b.y - a.y) / length * 4, y: (b.x - a.x) / length * 4)
                    let middle = CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)
                    var shadow = context; shadow.addFilter(.shadow(color: .black.opacity(0.23), radius: 1.5, x: 1, y: 2))
                    shadow.stroke(path, with: .color(Color(hex: 0x697780)), style: StrokeStyle(lineWidth: 9.2, lineCap: .round))
                    context.stroke(path, with: .linearGradient(steel, startPoint: CGPoint(x: middle.x - normal.x, y: middle.y - normal.y), endPoint: CGPoint(x: middle.x + normal.x, y: middle.y + normal.y)), style: StrokeStyle(lineWidth: 8, lineCap: .round))
                    // A fixed upper-left light produces a moving narrow reflection.
                    let facing = (-normal.x * 0.55 - normal.y * 0.83) / 4
                    let edge: CGFloat = facing > 0 ? 0.57 : -0.57
                    var highlight = Path()
                    highlight.move(to: CGPoint(x: a.x + normal.x * edge, y: a.y + normal.y * edge))
                    highlight.addLine(to: CGPoint(x: b.x + normal.x * edge, y: b.y + normal.y * edge))
                    context.stroke(highlight, with: .color(.white.opacity(0.75 + 0.25 * abs(facing))), style: StrokeStyle(lineWidth: 0.9, lineCap: .round))
                }
                for point in points {
                    let circle = Path(ellipseIn: CGRect(x: point.x - 6.7, y: point.y - 6.7, width: 13.4, height: 13.4))
                    var jointShadow = context
                    jointShadow.addFilter(.shadow(color: .black.opacity(0.23), radius: 1, x: 0.5, y: 1))
                    jointShadow.fill(circle, with: .color(Color(hex: 0xC5CFD6)))
                    context.fill(circle, with: .linearGradient(steel, startPoint: CGPoint(x: point.x - 5, y: point.y - 6), endPoint: CGPoint(x: point.x + 5, y: point.y + 6)))
                    context.stroke(circle, with: .color(Color(hex: 0x78858F)), lineWidth: 0.5)
                    let cap = Path(ellipseIn: CGRect(x: point.x - 4.5, y: point.y - 4.5, width: 9, height: 9))
                    context.fill(cap, with: .radialGradient(Gradient(colors: [.white, Color(hex: 0xE3E9ED), Color(hex: 0x9EAAB3)]), center: CGPoint(x: point.x - 1.5, y: point.y - 2), startRadius: 0, endRadius: 7))
                    context.stroke(cap, with: .color(.white.opacity(0.8)), lineWidth: 0.45)
                    var rim = Path(); rim.addArc(center: point, radius: 5.9, startAngle: .degrees(190), endAngle: .degrees(300), clockwise: false)
                    context.stroke(rim, with: .color(.white), style: StrokeStyle(lineWidth: 0.8, lineCap: .round))
                    var screw = Path(); screw.move(to: CGPoint(x: point.x - 2, y: point.y + 2)); screw.addLine(to: CGPoint(x: point.x + 2, y: point.y - 2))
                    context.stroke(screw, with: .color(Color(hex: 0x667681)), style: StrokeStyle(lineWidth: 0.75, lineCap: .round))
                    var slotEdge = context; slotEdge.translateBy(x: 0.65, y: 0.65)
                    slotEdge.stroke(screw, with: .color(.white.opacity(0.9)), lineWidth: 0.4)
                }
            }
            let top = LiftGeometry.boardTop(deployment) + LiftGeometry.boardHeight - 2
            let bottom = LiftGeometry.height
            let length = bottom - top
            var cable = Path(); cable.move(to: CGPoint(x: size.width / 2, y: top))
            for loop in 0..<10 {
                let y = top + CGFloat(loop) * length / 10
                cable.addCurve(to: CGPoint(x: size.width / 2, y: y + length / 10), control1: CGPoint(x: size.width / 2 - 6, y: y + length / 30), control2: CGPoint(x: size.width / 2 + 6, y: y + length / 15))
            }
            context.stroke(cable, with: .color(Color(hex: 0x495256)), style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
            context.stroke(cable, with: .color(Color(hex: 0xB1B8BB).opacity(0.65)), lineWidth: 0.6)
        }.allowsHitTesting(false).accessibilityHidden(true)
    }
}
