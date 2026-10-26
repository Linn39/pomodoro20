import Combine
import SwiftUI
import UserNotifications

struct ReminderView: View {
    @ObservedObject var controller: WatchReminderController
    private let ticker = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                Text("promodoro20")
                    .font(.headline)

                if !controller.hasSettings {
                    Image(systemName: "iphone.and.arrow.forward")
                        .font(.title2)
                    Text("Set up your schedule on iPhone.")
                        .multilineTextAlignment(.center)
                } else {
                    phaseContent
                }

                if controller.authorizationStatus == .denied {
                    Label("Enable notifications in Watch Settings to receive alerts.", systemImage: "bell.slash")
                        .font(.footnote)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.orange)
                }
                if let deliveryIssue = controller.deliveryIssue {
                    Text(deliveryIssue)
                        .font(.footnote)
                        .foregroundStyle(.orange)
                        .multilineTextAlignment(.center)
                }
                if let feedback = controller.feedback {
                    Text(feedback)
                        .font(.footnote)
                        .foregroundStyle(.orange)
                        .multilineTextAlignment(.center)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 8)
        }
        .onReceive(ticker) { _ in controller.tick() }
    }

    @ViewBuilder
    private var phaseContent: some View {
        switch controller.state.phase {
        case .inactive:
            Image(systemName: "moon.stars")
                .font(.title2)
            Text("Outside your active hours")
                .multilineTextAlignment(.center)
            if let opening = controller.nextOpening {
                Text("Next: \(opening, format: .dateTime.weekday(.wide).hour().minute())")
                    .font(.footnote)
                    .multilineTextAlignment(.center)
            }
        case .working(let due):
            Text("Working")
                .font(.title3.bold())
            countdown(until: due, prefix: "Next break in")
        case .waitingForRetry(let due):
            Text("Reminder missed")
                .font(.title3.bold())
            countdown(until: due, prefix: "Retry in")
        case .prompted:
            Text("Time for a break")
                .font(.title3.bold())
            Text("Look at something far away for 20 seconds.")
                .font(.footnote)
                .multilineTextAlignment(.center)
            Button("Start Break") { controller.startBreak() }
                .tint(.green)
            Button("Snooze \(controller.snoozeMinutes) min") { controller.snooze() }
        case .breaking(let end):
            Text("Look into the distance")
                .font(.title3.bold())
                .multilineTextAlignment(.center)
            countdown(until: end, prefix: "Break ends in")
        case .snoozed(let due):
            Text("Snoozed")
                .font(.title3.bold())
            countdown(until: due, prefix: "Next reminder in")
        }
    }

    private func countdown(until deadline: Date, prefix: String) -> some View {
        let remaining = max(0, Int(ceil(deadline.timeIntervalSince(controller.now))))
        let minutes = remaining / 60
        let seconds = remaining % 60
        return VStack(spacing: 2) {
            Text(prefix)
                .font(.footnote)
            Text(String(format: "%02d:%02d", minutes, seconds))
                .font(.system(.title, design: .rounded).monospacedDigit())
        }
    }
}
