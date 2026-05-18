import SwiftUI

struct WatchMissionView: View {
    @State private var isRunning = false
    @State private var secondsRemaining = 20 * 60

    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.06, green: 0.06, blue: 0.08),
                    Color.black
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: "mountain.2.fill")
                        .foregroundStyle(.green)
                    Text("The Climb")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                Text("Deep Work Block")
                    .font(.headline.weight(.semibold))
                    .lineLimit(2)
                Text(timeString)
                    .font(.system(.title, design: .rounded, weight: .bold))
                    .monospacedDigit()
                ProgressView(value: progress)
                    .tint(.green)
                Button(isRunning ? "Complete" : "Start Mission") {
                    if isRunning {
                        isRunning = false
                        secondsRemaining = 0
                    } else {
                        isRunning = true
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
            }
            .padding()
        }
        .onReceive(timer) { _ in
            guard isRunning, secondsRemaining > 0 else { return }
            secondsRemaining -= 1
        }
    }

    private var progress: Double {
        1 - Double(secondsRemaining) / Double(20 * 60)
    }

    private var timeString: String {
        let minutes = secondsRemaining / 60
        let seconds = secondsRemaining % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}
