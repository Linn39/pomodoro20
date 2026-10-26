import Foundation
import WatchConnectivity

/// Publishes the latest complete settings snapshot. Application context replaces
/// older snapshots, so a disconnected watch receives the current settings later.
final class PhoneWatchSync: NSObject, ObservableObject, WCSessionDelegate {
    @Published private(set) var status = "Connecting to Apple Watch…"

    private var pendingSettings: AppSettings?
    private let session: WCSession? = WCSession.isSupported() ? .default : nil

    override init() {
        super.init()
        guard let session else {
            status = "Apple Watch sync is unavailable on this device."
            return
        }
        session.delegate = self
        session.activate()
        updateStatus(for: session)
    }

    func publish(_ settings: AppSettings) {
        pendingSettings = settings
        guard let session else { return }
        guard session.activationState == .activated else {
            status = "Waiting to connect to Apple Watch…"
            return
        }
        sendLatest(using: session)
    }

    private func sendLatest(using session: WCSession) {
        guard let settings = pendingSettings else { return }
        guard session.isPaired else {
            status = "Pair an Apple Watch to sync your plans."
            return
        }
        guard session.isWatchAppInstalled else {
            status = "Install the watch app to sync your plans."
            return
        }

        do {
            let payload: [String: Any] = [
                "schemaVersion": 1,
                "settingsData": try JSONEncoder().encode(settings)
            ]
            try session.updateApplicationContext(payload)
            pendingSettings = nil
            status = "Settings queued for Apple Watch."
        } catch {
            status = "Could not sync settings: \(error.localizedDescription)"
        }
    }

    private func updateStatus(for session: WCSession) {
        guard session.activationState == .activated else {
            status = "Connecting to Apple Watch…"
            return
        }
        if pendingSettings != nil {
            sendLatest(using: session)
        } else if !session.isPaired {
            status = "Pair an Apple Watch to sync your plans."
        } else if !session.isWatchAppInstalled {
            status = "Install the watch app to sync your plans."
        } else {
            status = "Settings queued for Apple Watch."
        }
    }

    func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        DispatchQueue.main.async {
            if let error {
                self.status = "Could not connect to Apple Watch: \(error.localizedDescription)"
            } else {
                self.updateStatus(for: session)
            }
        }
    }

    func sessionDidBecomeInactive(_ session: WCSession) {
        DispatchQueue.main.async {
            self.status = "Apple Watch connection is changing…"
        }
    }

    func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }

    func sessionWatchStateDidChange(_ session: WCSession) {
        DispatchQueue.main.async {
            self.updateStatus(for: session)
        }
    }
}
