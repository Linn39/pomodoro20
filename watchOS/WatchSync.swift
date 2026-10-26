import Foundation
import WatchConnectivity

/// Receives the latest complete settings snapshot from the companion iPhone app.
final class WatchSync: NSObject, WCSessionDelegate {
    static let settingsKey = "settingsData"
    static let schemaVersionKey = "schemaVersion"
    static let supportedSchemaVersion = 1

    var onSettings: ((AppSettings) -> Void)?

    func activate() {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        session.delegate = self
        session.activate()
        accept(session.receivedApplicationContext)
    }

    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        guard activationState == .activated else { return }
        accept(session.receivedApplicationContext)
    }

    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        accept(applicationContext)
    }

    private func accept(_ context: [String: Any]) {
        guard let version = context[Self.schemaVersionKey] as? Int,
              version == Self.supportedSchemaVersion,
              let data = context[Self.settingsKey] as? Data,
              let settings = try? JSONDecoder().decode(AppSettings.self, from: data) else {
            return
        }
        DispatchQueue.main.async { [weak self] in
            self?.onSettings?(settings)
        }
    }
}
