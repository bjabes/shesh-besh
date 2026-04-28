import SwiftUI

public struct SplashView: View {
    private let onFinished: () -> Void

    @State private var diceLanded = false
    @State private var pulse = false
    @State private var titleVisible = false

    public init(onFinished: @escaping () -> Void) {
        self.onFinished = onFinished
    }

    public var body: some View {
        ZStack {
            LinenBrass.linen
                .ignoresSafeArea()

            RadialGradient(
                colors: [LinenBrass.linen, LinenBrass.linenDeep.opacity(0.55)],
                center: .center,
                startRadius: 80,
                endRadius: 460
            )
            .ignoresSafeArea()

            VStack(spacing: 36) {
                HStack(spacing: 22) {
                    DieView(value: 6, face: LinenBrass.cream, pip: LinenBrass.rust)
                        .rotationEffect(.degrees(diceLanded ? -7 : -120))
                        .offset(x: diceLanded ? 0 : -260, y: diceLanded ? 0 : -140)
                        .scaleEffect(diceLanded ? (pulse ? 1.07 : 1.0) : 0.4)
                        .opacity(diceLanded ? 1 : 0)
                    DieView(value: 5, face: LinenBrass.rust, pip: LinenBrass.cream)
                        .rotationEffect(.degrees(diceLanded ? 8 : 120))
                        .offset(x: diceLanded ? 0 : 260, y: diceLanded ? 0 : -140)
                        .scaleEffect(diceLanded ? (pulse ? 1.07 : 1.0) : 0.4)
                        .opacity(diceLanded ? 1 : 0)
                }

                Text("Shesh Besh")
                    .font(.system(size: 44, weight: .semibold, design: .serif))
                    .foregroundStyle(LinenBrass.ink)
                    .tracking(1.5)
                    .opacity(titleVisible ? 1 : 0)
                    .offset(y: titleVisible ? 0 : 12)
            }
        }
        .task { await runIntro() }
    }

    private func runIntro() async {
        do {
            withAnimation(.spring(response: 0.55, dampingFraction: 0.72)) {
                diceLanded = true
            }
            try await Task.sleep(for: .milliseconds(540))
            withAnimation(.spring(response: 0.22, dampingFraction: 0.5)) {
                pulse = true
            }
            try await Task.sleep(for: .milliseconds(140))
            withAnimation(.spring(response: 0.3, dampingFraction: 0.65)) {
                pulse = false
            }
            withAnimation(.easeOut(duration: 0.45)) {
                titleVisible = true
            }
            try await Task.sleep(for: .milliseconds(720))
            onFinished()
        } catch {
            return
        }
    }
}

private struct DieView: View {
    let value: Int
    let face: Color
    let pip: Color

    private static let dieSize: CGFloat = 96
    private static let cornerRadius: CGFloat = 20

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)
                .fill(face)
                .overlay(
                    RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)
                        .stroke(LinenBrass.brass.opacity(0.6), lineWidth: 1.2)
                )
                .shadow(color: LinenBrass.coffee.opacity(0.28), radius: 12, x: 0, y: 8)

            PipGrid(value: value, color: pip)
                .padding(Self.dieSize * 0.18)
        }
        .frame(width: Self.dieSize, height: Self.dieSize)
    }
}

private struct PipGrid: View {
    let value: Int
    let color: Color

    var body: some View {
        GeometryReader { proxy in
            let positions = pipPositions(in: proxy.size)
            let pipDiameter = proxy.size.width * 0.2
            ForEach(0..<positions.count, id: \.self) { idx in
                Circle()
                    .fill(color)
                    .frame(width: pipDiameter, height: pipDiameter)
                    .position(positions[idx])
            }
        }
    }

    private func pipPositions(in size: CGSize) -> [CGPoint] {
        let w = size.width
        let h = size.height
        let lx = w * 0.2
        let cx = w * 0.5
        let rx = w * 0.8
        let ty = h * 0.2
        let my = h * 0.5
        let by = h * 0.8

        switch value {
        case 1:
            return [CGPoint(x: cx, y: my)]
        case 2:
            return [CGPoint(x: lx, y: ty), CGPoint(x: rx, y: by)]
        case 3:
            return [CGPoint(x: lx, y: ty), CGPoint(x: cx, y: my), CGPoint(x: rx, y: by)]
        case 4:
            return [
                CGPoint(x: lx, y: ty), CGPoint(x: rx, y: ty),
                CGPoint(x: lx, y: by), CGPoint(x: rx, y: by)
            ]
        case 5:
            return [
                CGPoint(x: lx, y: ty), CGPoint(x: rx, y: ty),
                CGPoint(x: cx, y: my),
                CGPoint(x: lx, y: by), CGPoint(x: rx, y: by)
            ]
        case 6:
            return [
                CGPoint(x: lx, y: ty), CGPoint(x: rx, y: ty),
                CGPoint(x: lx, y: my), CGPoint(x: rx, y: my),
                CGPoint(x: lx, y: by), CGPoint(x: rx, y: by)
            ]
        default:
            return []
        }
    }
}

private enum LinenBrass {
    static let linen = Color(red: 0.937, green: 0.902, blue: 0.831)
    static let linenDeep = Color(red: 0.871, green: 0.785, blue: 0.647)
    static let cream = Color(red: 0.929, green: 0.886, blue: 0.800)
    static let coffee = Color(red: 0.420, green: 0.290, blue: 0.180)
    static let rust = Color(red: 0.659, green: 0.314, blue: 0.165)
    static let brass = Color(red: 0.722, green: 0.537, blue: 0.227)
    static let ink = Color(red: 0.126, green: 0.075, blue: 0.035)
}

#if DEBUG
#Preview {
    SplashView(onFinished: {})
}
#endif
