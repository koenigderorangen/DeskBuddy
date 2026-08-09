import Combine
import Sparkle

@MainActor
final class SoftwareUpdateController: ObservableObject {
    static let shared = SoftwareUpdateController()

    @Published private(set) var canCheckForUpdates = false

    private let updaterController: SPUStandardUpdaterController

    private init() {
        let publicKey = Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") as? String
        let isConfigured = !(publicKey?.isEmpty ?? true)
        updaterController = SPUStandardUpdaterController(
            startingUpdater: isConfigured,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )

        guard isConfigured else { return }
        updaterController.updater.publisher(for: \.canCheckForUpdates)
            .assign(to: &$canCheckForUpdates)
    }

    func checkForUpdates() {
        updaterController.checkForUpdates(nil)
    }
}