import CoreLocation
import CoreWLAN

/// Lists nearby Wi-Fi networks. macOS reveals network names only after Location access is granted.
@MainActor
final class WiFiScanner: NSObject, ObservableObject, CLLocationManagerDelegate {
    struct Result { var networks24: [String] = []; var only5GHz = 0; var current: String? }

    @Published var result = Result()
    @Published var scanning = false
    @Published var needsLocation = false
    private let location = CLLocationManager()

    override init() {
        super.init()
        location.delegate = self
    }

    func scan() {
        switch location.authorizationStatus {
        case .notDetermined: location.requestWhenInUseAuthorization(); return  // scan resumes in the delegate
        case .denied, .restricted: needsLocation = true; return
        default: needsLocation = false
        }
        scanning = true
        Task.detached {
            let iface = CWWiFiClient.shared().interface()
            let networks = (try? iface?.scanForNetworks(withSSID: nil)) ?? []
            var bands: [String: Set<CWChannelBand>] = [:]
            for n in networks {
                guard let ssid = n.ssid, !ssid.isEmpty, let band = n.wlanChannel?.channelBand else { continue }
                bands[ssid, default: []].insert(band)
            }
            let sorted = { (a: String, b: String) in a.localizedStandardCompare(b) == .orderedAscending }
            let r = Result(networks24: bands.filter { $0.value.contains(.band2GHz) }.keys.sorted(by: sorted),
                           only5GHz: bands.filter { !$0.value.contains(.band2GHz) }.count,
                           current: iface?.ssid())
            await MainActor.run { self.result = r; self.scanning = false }
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            if manager.authorizationStatus != .notDetermined { self.scan() }
        }
    }
}
