import SwiftUI

/// A small native mark with appearance-aware colors and clean edges at sidebar sizes.
struct ChatHarborMark: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Canvas { context, size in
            context.scaleBy(x: size.width / 128, y: size.height / 128)
            let ink = colorScheme == .dark
                ? Color(red: 0.89, green: 0.92, blue: 0.95)
                : Color(red: 0.16, green: 0.36, blue: 0.60)
            let blue = colorScheme == .dark
                ? Color(red: 0.47, green: 0.71, blue: 0.86)
                : Color(red: 0.20, green: 0.48, blue: 0.75)
            let sails = Path { p in
                p.move(to: CGPoint(x: 60, y: 34))
                p.addLine(to: CGPoint(x: 60, y: 84))
                p.addLine(to: CGPoint(x: 36, y: 78))
                p.closeSubpath()
                p.move(to: CGPoint(x: 65, y: 29))
                p.addLine(to: CGPoint(x: 65, y: 84))
                p.addLine(to: CGPoint(x: 91, y: 77))
                p.closeSubpath()
            }
            context.fill(sails, with: .color(ink))
            let hull = Path { p in
                p.move(to: CGPoint(x: 29, y: 88))
                p.addLine(to: CGPoint(x: 99, y: 88))
                p.addQuadCurve(to: CGPoint(x: 64, y: 107), control: CGPoint(x: 91, y: 111))
                p.addQuadCurve(to: CGPoint(x: 29, y: 88), control: CGPoint(x: 37, y: 107))
            }
            context.fill(hull, with: .color(ink))
            let bubble = Path(roundedRect: CGRect(x: 78, y: 18, width: 36, height: 25), cornerRadius: 8)
            context.fill(bubble, with: .color(ink))
            let tail = Path { p in
                p.move(to: CGPoint(x: 85, y: 41))
                p.addLine(to: CGPoint(x: 83, y: 51))
                p.addLine(to: CGPoint(x: 96, y: 41))
                p.closeSubpath()
            }
            context.fill(tail, with: .color(ink))
            for x in [85.0, 94.0, 103.0] {
                context.fill(Path(ellipseIn: CGRect(x: x, y: 28, width: 4, height: 4)), with: .color(blue))
            }
            let wave = Path { p in
                p.move(to: CGPoint(x: 23, y: 108))
                p.addCurve(to: CGPoint(x: 105, y: 108), control1: CGPoint(x: 49, y: 96), control2: CGPoint(x: 73, y: 120))
            }
            context.stroke(wave, with: .color(blue), style: StrokeStyle(lineWidth: 5, lineCap: .round))
        }
        .accessibilityHidden(true)
    }
}
