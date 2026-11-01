import SwiftUI

// MARK: - 液态玻璃材质

/// 三层结构：毛玻璃底 + 高光边缘 + 跟随手指的光斑
struct LiquidGlass: ViewModifier {
    var corner: CGFloat = 22
    var glow: CGPoint = .init(x: 0.25, y: 0.15)
    var intensity: Double = 1.0

    func body(content: Content) -> some View {
        content
            .background {
                ZStack {
                    // 1. 基础毛玻璃
                    RoundedRectangle(cornerRadius: corner, style: .continuous)
                        .fill(.ultraThinMaterial)

                    // 2. 跟随光斑的白色径向高光
                    GeometryReader { geo in
                        RadialGradient(
                            colors: [Color.white.opacity(0.55 * intensity),
                                     Color.white.opacity(0.10 * intensity),
                                     Color.clear],
                            center: UnitPoint(x: glow.x, y: glow.y),
                            startRadius: 0,
                            endRadius: geo.size.width * 0.85
                        )
                    }
                    .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))

                    // 3. 淡紫内透，避免纯白死板
                    RoundedRectangle(cornerRadius: corner, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [Color(red: 0.90, green: 0.88, blue: 1.0).opacity(0.22),
                                         Color.clear,
                                         Color(red: 0.86, green: 0.92, blue: 1.0).opacity(0.16)],
                                startPoint: .topLeading, endPoint: .bottomTrailing
                            )
                        )
                }
            }
            .overlay {
                // 4. 玻璃边缘：上亮下暗的描边
                RoundedRectangle(cornerRadius: corner, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [Color.white.opacity(0.95),
                                     Color.white.opacity(0.35),
                                     Color(red: 0.65, green: 0.66, blue: 0.95).opacity(0.22)],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            }
            .overlay {
                // 5. 内侧顶部高光线（玻璃厚度感）
                RoundedRectangle(cornerRadius: corner, style: .continuous)
                    .inset(by: 1)
                    .strokeBorder(
                        LinearGradient(colors: [Color.white.opacity(0.85), Color.clear],
                                       startPoint: .top, endPoint: .center),
                        lineWidth: 0.8
                    )
            }
            .shadow(color: Color(red: 0.39, green: 0.40, blue: 0.95).opacity(0.10),
                    radius: 22, x: 0, y: 8)
            .shadow(color: Color.black.opacity(0.03), radius: 2, x: 0, y: 1)
    }
}

extension View {
    func liquidGlass(corner: CGFloat = 22, glow: CGPoint = .init(x: 0.25, y: 0.15), intensity: Double = 1) -> some View {
        modifier(LiquidGlass(corner: corner, glow: glow, intensity: intensity))
    }
}

// MARK: - 会动的背景

struct AuroraBackground: View {

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color(red: 0.972, green: 0.965, blue: 1.0)

                // 一个主光斑跟随手指
                Blob(color: Color(red: 0.815, green: 0.780, blue: 1.0),
                     size: geo.size.width * 1.05)
                    .position(x: geo.size.width * 0.3, y: geo.size.height * 0.12)
                    .blur(radius: 60)
                    .opacity(0.75)

                // 两个缓慢漂移的辅助色块
                Blob(color: Color(red: 0.760, green: 0.898, blue: 0.980),
                     size: geo.size.width * 0.92)
                    .position(x: geo.size.width * 0.18, y: geo.size.height * 0.62)
                    .blur(radius: 70)
                    .opacity(0.62)

                Blob(color: Color(red: 0.960, green: 0.820, blue: 0.900),
                     size: geo.size.width * 0.80)
                    .position(x: geo.size.width * 0.85, y: geo.size.height * 0.90)
                    .blur(radius: 70)
                    .opacity(0.48)
            }
            .allowsHitTesting(false)      // 背景绝不接受触摸，手势全留给 ScrollView
            .ignoresSafeArea()
        }
    }
}

struct Blob: View {
    let color: Color
    let size: CGFloat
    var body: some View {
        Circle()
            .fill(RadialGradient(colors: [color, color.opacity(0.0)],
                                 center: .center,
                                 startRadius: 0,
                                 endRadius: size / 2))
            .frame(width: size, height: size)
    }
}
