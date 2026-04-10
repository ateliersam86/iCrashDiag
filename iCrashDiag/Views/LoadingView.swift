import SwiftUI

// MARK: - Full-screen loading overlay

struct LoadingView: View {
    let progress: Double
    let parsed: Int
    let total: Int
    let currentFile: String

    @State private var pulse = false
    @State private var dotPhase = 0

    private let timer = Timer.publish(every: 0.45, on: .main, in: .common).autoconnect()

    var body: some View {
        ZStack {
            // Blurred backdrop
            Rectangle()
                .fill(.ultraThinMaterial)
                .ignoresSafeArea()

            VStack(spacing: 28) {
                // Animated icon
                ZStack {
                    // Outer glow ring
                    Circle()
                        .stroke(Color.orange.opacity(0.15), lineWidth: 12)
                        .frame(width: 96, height: 96)
                        .scaleEffect(pulse ? 1.12 : 1.0)
                        .opacity(pulse ? 0 : 0.6)
                        .animation(
                            .easeOut(duration: 1.2).repeatForever(autoreverses: false),
                            value: pulse
                        )

                    // Progress ring
                    Circle()
                        .trim(from: 0, to: progress)
                        .stroke(
                            AngularGradient(
                                colors: [.orange.opacity(0.4), .orange],
                                center: .center
                            ),
                            style: StrokeStyle(lineWidth: 4, lineCap: .round)
                        )
                        .frame(width: 84, height: 84)
                        .rotationEffect(.degrees(-90))
                        .animation(.linear(duration: 0.15), value: progress)

                    // Icon bg
                    Circle()
                        .fill(Color(red: 0.11, green: 0.13, blue: 0.19))
                        .frame(width: 72, height: 72)

                    Image(systemName: "stethoscope")
                        .font(.system(size: 30, weight: .light))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.orange, Color(red: 1, green: 0.5, blue: 0.2)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                }
                .onAppear { pulse = true }

                // Counter + percent
                VStack(spacing: 6) {
                    HStack(alignment: .lastTextBaseline, spacing: 4) {
                        Text("\(parsed)")
                            .font(.system(size: 36, weight: .bold, design: .monospaced))
                            .contentTransition(.numericText(countsDown: false))
                            .animation(.spring(response: 0.3), value: parsed)
                        Text("/ \(total)")
                            .font(.system(size: 18, weight: .regular, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .opacity(total > 0 ? 1 : 0)
                    }

                    Text("crash logs analysed")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                // File name ticker
                if !currentFile.isEmpty {
                    HStack(spacing: 6) {
                        Image(systemName: "doc.text")
                            .font(.caption2)
                            .foregroundStyle(.orange.opacity(0.7))
                        Text(currentFile)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .frame(maxWidth: 320)
                            .transition(.asymmetric(
                                insertion: .move(edge: .trailing).combined(with: .opacity),
                                removal: .move(edge: .leading).combined(with: .opacity)
                            ))
                            .id(currentFile)
                            .animation(.easeInOut(duration: 0.18), value: currentFile)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 6)
                    .background(.quaternary, in: Capsule())
                }

                // Progress bar
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color.secondary.opacity(0.12))
                            .frame(height: 4)

                        Capsule()
                            .fill(
                                LinearGradient(
                                    colors: [Color.orange.opacity(0.7), Color.orange],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: geo.size.width * progress, height: 4)
                            .animation(.linear(duration: 0.12), value: progress)
                    }
                }
                .frame(height: 4)
                .frame(maxWidth: 300)
            }
            .padding(40)
        }
        .transition(.opacity.animation(.easeInOut(duration: 0.3)))
    }
}
