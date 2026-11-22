import Foundation
import idevice

enum LocationEngineError: LocalizedError {
    case invalidIP
    case pairingRead
    case tunnelCreate
    case remoteServer
    case simulationCreate
    case locationSet
    case locationClear
    case notActive

    var errorDescription: String? {
        let base: String
        switch self {
        case .invalidIP: base = "IP đường hầm không hợp lệ. Vào Cài đặt → IP đường hầm (thường là 10.7.0.1)."
        case .pairingRead: base = "Không đọc được file pairing. Vào Cài đặt › Ghép nối ngay trên iPhone để tạo lại."
        case .tunnelCreate: base = "Không mở được đường hầm developer. Kiểm tra: LocalDevVPN đang bật, đang dùng Wi‑Fi. iOS 26.4 trở lên phải ghép nối lại: Cài đặt › Ghép nối ngay trên iPhone."
        case .remoteServer: base = "Đã vào đường hầm nhưng bắt tay RemoteXPC thất bại."
        case .simulationCreate: base = "Không mở được dịch vụ giả lập vị trí của Apple."
        case .locationSet: base = "Không đặt được tọa độ giả lập."
        case .locationClear: base = "Không xóa được vị trí giả lập."
        case .notActive: base = "Chưa có phiên giả lập nào đang chạy."
        }
        let detail = LocationEngine.lastDetail
        return detail.isEmpty ? base : base + "\n\nChi tiết: " + detail
    }

    static func from(code: Int32) -> LocationEngineError {
        switch code {
        case 1: return .invalidIP
        case 2: return .pairingRead
        case 3: return .tunnelCreate
        case 9: return .remoteServer
        case 10: return .simulationCreate
        case 11: return .locationSet
        case 12: return .locationClear
        default: return .locationSet
        }
    }
}

/// Thin Swift wrapper around idevice’s DVT location simulation (injects into locationd).
enum LocationEngine {
    private static let queue = DispatchQueue(label: "com.chrismack.locus.location", qos: .userInitiated)

    private static var adapter: OpaquePointer?
    private static var handshake: OpaquePointer?
    private static var remoteServer: OpaquePointer?
    private static var locationSimulation: OpaquePointer?

    private static let ok: Int32 = 0
    private static let invalidIP: Int32 = 1
    private static let pairingRead: Int32 = 2
    private static let tunnelCreate: Int32 = 3
    private static let remoteServerCode: Int32 = 9
    private static let simulationCreate: Int32 = 10
    private static let locationSet: Int32 = 11
    private static let locationClear: Int32 = 12

    static var isSessionActive: Bool { locationSimulation != nil }

    /// Thông báo lỗi gốc từ thư viện idevice (để chẩn đoán).
    static var lastDetail = ""

    /// Ghi lại lỗi gốc rồi giải phóng.
    private static func note(_ err: UnsafeMutablePointer<IdeviceFfiError>, _ stage: String) {
        let message = err.pointee.message.map { String(cString: $0) } ?? ""
        lastDetail = "\(stage) [\(err.pointee.code)] \(message)"
        idevice_error_free(err)
    }

    static func set(latitude: Double, longitude: Double, pairingPath: String, deviceIP: String) -> Result<Void, LocationEngineError> {
        var result: Result<Void, LocationEngineError> = .failure(.locationSet)
        queue.sync {
            let code = setLocked(latitude: latitude, longitude: longitude, pairingPath: pairingPath, deviceIP: deviceIP)
            result = code == ok ? .success(()) : .failure(.from(code: code))
        }
        return result
    }

    static func clear() -> Result<Void, LocationEngineError> {
        var result: Result<Void, LocationEngineError> = .failure(.notActive)
        queue.sync {
            let code = clearLocked()
            result = code == ok ? .success(()) : .failure(.from(code: code))
        }
        return result
    }

    private static func cleanup() {
        if let locationSimulation {
            location_simulation_free(locationSimulation)
            self.locationSimulation = nil
        }
        if let remoteServer {
            remote_server_free(remoteServer)
            self.remoteServer = nil
        }
        if let handshake {
            rsd_handshake_free(handshake)
            self.handshake = nil
        }
        if let adapter {
            adapter_free(adapter)
            self.adapter = nil
        }
    }

    private static func setLocked(latitude: Double, longitude: Double, pairingPath: String, deviceIP: String) -> Int32 {
        lastDetail = ""
        if let locationSimulation {
            if let err = location_simulation_set(locationSimulation, latitude, longitude) {
                note(err, "set (phiên cũ)")
                cleanup()
            } else {
                return ok
            }
        }

        var address = sockaddr_in()
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = in_port_t(49152).bigEndian
        let inetResult = deviceIP.withCString { inet_pton(AF_INET, $0, &address.sin_addr) }
        guard inetResult == 1 else { return invalidIP }

        // 1) File RPPairing (tạo bằng idevice_pair)
        var rpHandle: OpaquePointer?
        if let rpError = pairingPath.withCString({ rp_pairing_file_read($0, &rpHandle) }) {
            note(rpError, "đọc RPPairing")
            rpHandle = nil
        }

        if let rpHandle {
            defer { rp_pairing_file_free(rpHandle) }
            let providerError = withUnsafePointer(to: &address) { pointer in
                pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    tunnel_create_rppairing(
                        $0,
                        socklen_t(MemoryLayout<sockaddr_in>.stride),
                        "LocusLocation",
                        rpHandle,
                        nil,
                        nil,
                        &adapter,
                        &handshake
                    )
                }
            }
            if let providerError {
                note(providerError, "tạo đường hầm RPPairing")
                cleanup()
                return tunnelCreate
            }
        } else {
            // 2) File pairing của SideStore / jitterbugpair (.mobiledevicepairing)
            //    lockdown → CoreDeviceProxy → TCP adapter → RSD (cách StikDebug dùng)
            let code = openLockdownTunnel(pairingPath: pairingPath, ip: deviceIP)
            if code != ok {
                cleanup()
                return code
            }
        }

        if let remoteServerError = remote_server_connect_rsd(adapter, handshake, &remoteServer) {
            note(remoteServerError, "kết nối RemoteServer")
            cleanup()
            return remoteServerCode
        }

        if let simError = location_simulation_new(remoteServer, &locationSimulation) {
            note(simError, "mở location_simulation")
            cleanup()
            return simulationCreate
        }
        // location_simulation_new consumes/owns remote server lifecycle alongside handle
        remoteServer = nil

        if let setError = location_simulation_set(locationSimulation, latitude, longitude) {
            note(setError, "đặt tọa độ")
            cleanup()
            return locationSet
        }
        return ok
    }

    private static func openLockdownTunnel(pairingPath: String, ip: String) -> Int32 {
        var lockdownAddress = sockaddr_in()
        lockdownAddress.sin_family = sa_family_t(AF_INET)
        lockdownAddress.sin_port = in_port_t(62078).bigEndian
        let inetResult = ip.withCString { inet_pton(AF_INET, $0, &lockdownAddress.sin_addr) }
        guard inetResult == 1 else { return invalidIP }

        var pairingFile: OpaquePointer?
        if let err = pairingPath.withCString({ idevice_pairing_file_read($0, &pairingFile) }) {
            note(err, "đọc file pairing SideStore")
            return pairingRead
        }
        guard let pairingFile else { return pairingRead }

        // pairing_file bị provider tiêu thụ, không free lại.
        var provider: OpaquePointer?
        let providerError = withUnsafePointer(to: &lockdownAddress) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                idevice_tcp_provider_new($0, pairingFile, "MyLocal", &provider)
            }
        }
        if let providerError {
            note(providerError, "kết nối lockdown 62078")
            return tunnelCreate
        }
        guard let provider else { return tunnelCreate }
        defer { idevice_provider_free(provider) }

        var proxy: OpaquePointer?
        if let err = core_device_proxy_connect(provider, &proxy) {
            note(err, "CoreDeviceProxy")
            return tunnelCreate
        }
        guard let proxy else { return tunnelCreate }

        var rsdPort: UInt16 = 0
        if let err = core_device_proxy_get_server_rsd_port(proxy, &rsdPort) {
            note(err, "lấy cổng RSD")
            core_device_proxy_free(proxy)
            return tunnelCreate
        }

        // proxy bị adapter tiêu thụ.
        if let err = core_device_proxy_create_tcp_adapter(proxy, &adapter) {
            note(err, "tạo TCP adapter")
            return tunnelCreate
        }

        var stream: OpaquePointer?
        if let err = adapter_connect(adapter, rsdPort, &stream) {
            note(err, "kết nối cổng RSD")
            return remoteServerCode
        }

        // stream bị handshake tiêu thụ.
        if let err = rsd_handshake_new(stream, &handshake) {
            note(err, "bắt tay RSD")
            return remoteServerCode
        }
        return ok
    }

    private static func clearLocked() -> Int32 {
        guard let locationSimulation else { return locationClear }
        let err = location_simulation_clear(locationSimulation)
        cleanup()
        if let err {
            note(err, "xóa giả lập")
            return locationClear
        }
        return ok
    }
}
