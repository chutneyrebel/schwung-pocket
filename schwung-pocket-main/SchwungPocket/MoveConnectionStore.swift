import Foundation
import Combine

struct SavedMoveProfile: Codable, Identifiable, Equatable {
    var id: String
    var name: String
    var address: String
}

@MainActor
final class MoveConnectionStore: ObservableObject {
    enum Status: Equatable {
        case idle
        case checking
        case connected
        case failed(String)

        var title: String {
            switch self {
            case .idle: return "Not checked yet"
            case .checking: return "Checking Move…"
            case .connected: return "Move is reachable"
            case .failed: return "Can't reach Move"
            }
        }

        var detail: String {
            switch self {
            case .idle: return "Connect your iPhone and Move to the same Wi-Fi network."
            case .checking: return "Trying the Schwung Manager address."
            case .connected: return "Schwung Manager responded on your local network."
            case .failed(let message): return message
            }
        }
    }

    @Published var addressText: String {
        didSet {
            UserDefaults.standard.set(addressText, forKey: Self.addressKey)
            status = .idle
            lastCheckedAt = nil
        }
    }
    @Published private(set) var status: Status = .idle
    @Published private(set) var lastCheckedAt: Date?

    private static let addressKey = "SchwungPocket.MoveAddress"
    static let defaultAddress = "move.local:7700"
    private var monitorTask: Task<Void, Never>?

    init() {
        let defaults = UserDefaults.standard
        let storedAddress = defaults.string(forKey: Self.addressKey) ?? Self.defaultAddress
        let profiles: [SavedMoveProfile] = {
            guard let json = defaults.string(forKey: "SchwungPocket.SavedMoves.v1"),
                  let data = json.data(using: .utf8),
                  let decoded = try? JSONDecoder().decode([SavedMoveProfile].self, from: data) else { return [] }
            return decoded
        }()
        let selectedID = defaults.string(forKey: "SchwungPocket.SelectedMoveID.v1") ?? ""
        let defaultID = defaults.string(forKey: "SchwungPocket.DefaultMoveID.v1") ?? ""
        let activeProfile = profiles.first(where: { $0.id == selectedID })
            ?? profiles.first(where: { $0.id == defaultID })
        addressText = activeProfile?.address ?? storedAddress
        if let activeProfile {
            defaults.set(activeProfile.id, forKey: "SchwungPocket.SelectedMoveID.v1")
            defaults.set(activeProfile.address, forKey: Self.addressKey)
        }
    }

    private var baseComponents: URLComponents? {
        let value = addressText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return nil }
        let input = value.contains("://") ? value : "http://\(value)"
        guard var components = URLComponents(string: input),
              let scheme = components.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              let host = components.host, !host.isEmpty else {
            return nil
        }
        components.scheme = scheme
        components.path = ""
        components.query = nil
        components.fragment = nil
        return components
    }

    var managerURL: URL? {
        guard var components = baseComponents else { return nil }
        components.path = "/"
        return components.url
    }

    var mirrorURL: URL? {
        guard var components = baseComponents else { return nil }
        components.path = "/mirror"
        return components.url
    }

    /// Checks immediately on foreground, then retries while the app remains active.
    /// iOS suspends background apps, so this intentionally does not promise background polling.
    func startMonitoring(intervalSeconds: UInt64 = 25) {
        guard monitorTask == nil else { return }
        monitorTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                await self.checkConnection()
                do {
                    try await Task.sleep(nanoseconds: intervalSeconds * 1_000_000_000)
                } catch {
                    return
                }
            }
        }
    }

    func stopMonitoring() {
        monitorTask?.cancel()
        monitorTask = nil
        if status == .checking {
            status = .idle
        }
    }

    func checkConnection() async {
        if case .checking = status { return }
        let requestedAddress = addressText
        guard let url = managerURL else {
            status = .failed("Enter a valid address such as move.local:7700.")
            lastCheckedAt = Date()
            return
        }

        status = .checking
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 6
        request.cachePolicy = .reloadIgnoringLocalCacheData

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            guard !Task.isCancelled, addressText == requestedAddress else { return }
            lastCheckedAt = Date()
            if let http = response as? HTTPURLResponse, (200..<500).contains(http.statusCode) {
                status = .connected
            } else {
                status = .failed("A response arrived, but it did not look like a working Schwung Manager. Check the address and port.")
            }
        } catch {
            guard !Task.isCancelled, addressText == requestedAddress else { return }
            lastCheckedAt = Date()
            status = .failed("No response. Check that Move is powered on, Schwung is running, and your iPhone is on the same Wi-Fi. You can also try Move's IP address with port 7700. (\(error.localizedDescription))")
        }
    }

    func resetAddress() {
        addressText = Self.defaultAddress
    }
}
