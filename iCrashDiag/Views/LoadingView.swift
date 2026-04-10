import SwiftUI

struct LoadingView: View {
    let stage: LoadingStage
    let progress: Double
    let parsed: Int
    let total: Int
    let currentFile: String
    let message: String

    @State private var pulseScale: CGFloat = 1.0
    @State private var displayedFile: String = ""
    @State private var fileUpdateTimer: Timer? = nil

    var body: some View {
        ZStack {
            Rectangle()
                .fill(.ultraThinMaterial)
                .ignoresSafeArea()

            VStack(spacing: 32) {

                // --- Progress ring + icon ---
                ZStack {
                    // Pulse ring
                    Circle()
                        .stroke(Color.orange.opacity(0.12), lineWidth: 14)
                        .frame(width: 104, height: 104)
                        .scaleEffect(pulseScale)
                        .opacity(2.0 - pulseScale)

                    // Arc progress
                    Circle()
                        .trim(from: 0, to: max(0.02, progress))
                        .stroke(
                            AngularGradient(
                                colors: [Color.orange.opacity(0.3), Color.orange],
                                center: .center,
                                startAngle: .degrees(0),
                                endAngle: .degrees(360)
                            ),
                            style: StrokeStyle(lineWidth: 4, lineCap: .round)
                        )
                        .frame(width: 88, height: 88)
                        .rotationEffect(.degrees(-90))
                        .animation(.linear(duration: 0.2), value: progress)

                    // Icon background
                    Circle()
                        .fill(Color(red: 0.09, green: 0.11, blue: 0.18))
                        .frame(width: 74, height: 74)

                    // Stage-specific icon
                    Image(systemName: stageIcon)
                        .font(.system(size: 28, weight: .light))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [Color.orange, Color(red: 1, green: 0.5, blue: 0.2)],
                                startPoint: .topLeading, endPoint: .bottomTrailing
                            )
                        )
                        .contentTransition(.symbolEffect(.replace))
                        .animation(.easeInOut(duration: 0.3), value: stageIcon)
                }
                .onAppear { startPulse() }

                // --- Counter ---
                VStack(spacing: 5) {
                    if total > 0 {
                        HStack(alignment: .lastTextBaseline, spacing: 4) {
                            Text("\(parsed)")
                                .font(.system(size: 40, weight: .bold, design: .monospaced))
                                .contentTransition(.numericText(countsDown: false))
                                .animation(.spring(response: 0.25), value: parsed)

                            Text("/ \(total)")
                                .font(.system(size: 20, weight: .regular, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                    }

                    Text(message)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .contentTransition(.opacity)
                        .animation(.easeInOut(duration: 0.3), value: message)
                }

                // --- Current file ticker ---
                ZStack {
                    Capsule()
                        .fill(Color.primary.opacity(0.06))
                        .frame(width: 340, height: 30)

                    if !displayedFile.isEmpty {
                        HStack(spacing: 6) {
                            Image(systemName: "doc.text")
                                .font(.system(size: 10))
                                .foregroundStyle(.orange.opacity(0.6))
                            Text(displayedFile)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .frame(maxWidth: 300)
                        }
                        .transition(.opacity)
                        .id(displayedFile)
                    } else {
                        Text(stageLabel)
                            .font(.system(size: 11))
                            .foregroundStyle(.tertiary)
                            .transition(.opacity)
                    }
                }
                .animation(.easeInOut(duration: 0.15), value: displayedFile)

                // --- Progress bar ---
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.secondary.opacity(0.1)).frame(height: 3)
                        Capsule()
                            .fill(LinearGradient(
                                colors: [Color.orange.opacity(0.6), Color.orange],
                                startPoint: .leading, endPoint: .trailing
                            ))
                            .frame(width: max(6, geo.size.width * progress), height: 3)
                            .animation(.linear(duration: 0.15), value: progress)
                    }
                }
                .frame(height: 3)
                .frame(maxWidth: 300)
            }
            .padding(48)
        }
        .onChange(of: currentFile) { _, new in
            // Throttle file name updates to avoid visual jank
            guard !new.isEmpty else { return }
            displayedFile = new
        }
        .onChange(of: stage) { _, new in
            if case .analyzing = new {
                displayedFile = ""
            }
        }
        .transition(.opacity.animation(.easeInOut(duration: 0.25)))
    }

    private var stageIcon: String {
        switch stage {
        case .idle, .scanning:           return "magnifyingglass"
        case .parsing:                   return "doc.text.magnifyingglass"
        case .analyzing:                 return "chart.bar.doc.horizontal"
        case .done:                      return "checkmark.circle"
        }
    }

    private var stageLabel: String {
        switch stage {
        case .scanning:    return "Scanning folder…"
        case .parsing:     return "Parsing crash logs…"
        case .analyzing:   return "Building analysis report…"
        case .done:        return "Complete"
        default:           return ""
        }
    }

    private func startPulse() {
        withAnimation(.easeOut(duration: 1.4).repeatForever(autoreverses: false)) {
            pulseScale = 1.18
        }
    }
}
