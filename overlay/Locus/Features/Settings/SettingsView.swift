import UIKit
import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @EnvironmentObject private var pairing: PairingStore
    @EnvironmentObject private var session: SpoofSession
    @Environment(\.dismiss) private var dismiss

    @State private var showImporter = false
    @State private var showPairOnDevice = false
    @State private var showNameEasterEgg = false
    @State private var tunnelIP = TunnelConfig.targetIP
    @State private var localDevVPNInstalled = LocalDevVPN.isInstalled
    @Environment(\.scenePhase) private var scenePhase

    private var supportsOnDevicePairing: Bool {
        ProcessInfo.processInfo.operatingSystemVersion.majorVersion >= 27
    }

    private var detectedOSText: String {
        var size = 0
        sysctlbyname("kern.osproductversion", nil, &size, nil, 0)
        var buffer = [CChar](repeating: 0, count: max(size, 1))
        sysctlbyname("kern.osproductversion", &buffer, &size, nil, 0)
        let kernel = String(cString: buffer)
        return "Phiên bản iOS app đọc được: \(UIDevice.current.systemVersion) (hệ thống: \(kernel))"
    }

    private var appVersion: String {
        let short = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? ""
        return build.isEmpty ? short : "\(short) (\(build))"
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Label {
                        Text(pairing.hasPairingFile ? "Đã có file pairing" : "Chưa có file pairing")
                    } icon: {
                        Image(systemName: pairing.hasPairingFile ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                            .foregroundStyle(pairing.hasPairingFile ? LocusTheme.statusGood : LocusTheme.statusWarn)
                    }

                    if supportsOnDevicePairing {
                        Button {
                            showPairOnDevice = true
                        } label: {
                            Label("Ghép nối ngay trên iPhone (iOS 27)", systemImage: "iphone.gen3.radiowaves.left.and.right")
                        }
                    }

                    Button("Nhập file pairing…") { showImporter = true }
                    Button("Dán file pairing từ bộ nhớ tạm") {
                        do {
                            try pairing.importPairingFromClipboard()
                        } catch {
                            session.lastError = error.localizedDescription
                        }
                    }
                    if pairing.hasPairingFile {
                        Button("Xóa file pairing", role: .destructive) {
                            try? pairing.removePairing()
                        }
                    }
                } header: {
                    Text("Ghép nối developer")
                } footer: {
                    Text("iOS 26: cần file RPPairing tạo 1 lần bằng idevice_pair trên máy tính (file của SideStore không dùng được). iOS 27: bấm Ghép nối ngay trên iPhone.\n\n" + detectedOSText)
                }

                Section {
                    TextField("IP đường hầm", text: $tunnelIP)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .onSubmit {
                            TunnelConfig.setTargetIP(tunnelIP)
                        }
                    LabeledContent("Trạng thái") {
                        Text(LocalDevVPN.isConnected ? "Đã kết nối" : "Chưa kết nối")
                            .foregroundStyle(LocalDevVPN.isConnected ? LocusTheme.statusGood : LocusTheme.statusWarn)
                    }
                    Button("Lưu IP đường hầm") {
                        TunnelConfig.setTargetIP(tunnelIP)
                    }
                    Button {
                        if localDevVPNInstalled {
                            LocalDevVPN.openInstalled()
                        } else {
                            LocalDevVPN.openAppStore()
                        }
                    } label: {
                        Label(
                            localDevVPNInstalled ? "Mở LocalDevVPN" : "Tải LocalDevVPN (App Store)",
                            systemImage: localDevVPNInstalled ? "lock.shield.fill" : "arrow.down.app.fill"
                        )
                    }
                } header: {
                    Text("Đường hầm")
                } footer: {
                    Text("Bật LocalDevVPN trước khi dịch chuyển. IP mặc định là 10.7.0.1. Lần đầu hãy dịch chuyển khi đang dùng Wi‑Fi, sau đó có thể chuyển sang 4G/5G.")
                }

                Section("Quyền riêng tư") {
                    Text("Chạy hoàn toàn trên máy. Điểm yêu thích và lịch sử lưu trong máy, không gửi dữ liệu đi đâu.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("Thông tin") {
                    LabeledContent("Phiên bản", value: appVersion)
                    LabeledContent("Công nghệ", value: "idevice DVT location simulation")
                    Text("Dựa trên Locus (mã nguồn mở, MIT). Giả lập vị trí dùng thư viện idevice FFI (MIT).")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section {
                    Button {
                        showNameEasterEgg = true
                    } label: {
                        Text("locus: tiếng Latin nghĩa là nơi chốn.")
                            .font(.footnote.italic())
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 4)
                    }
                    .buttonStyle(.plain)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                }
            }
            .navigationTitle("Cài đặt")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Xong") {
                        TunnelConfig.setTargetIP(tunnelIP)
                        dismiss()
                    }
                }
            }
            .sheet(isPresented: $showImporter) {
            PairingDocumentPicker(
                onPick: { url in
                    showImporter = false
                    do {
                        try pairing.importPairing(from: url)
                    } catch {
                        session.lastError = error.localizedDescription
                    }
                },
                onCancel: { showImporter = false }
            )
            .ignoresSafeArea()
        }
            .sheet(isPresented: $showPairOnDevice) {
                PairOnDeviceView()
                    .environmentObject(pairing)
            }
            .fullScreenCover(isPresented: $showNameEasterEgg) {
                LocusEasterEggView()
            }
            .onAppear {
                localDevVPNInstalled = LocalDevVPN.isInstalled
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active {
                    localDevVPNInstalled = LocalDevVPN.isInstalled
                }
            }
        }
    }
}

struct PlacesView: View {
    @EnvironmentObject private var session: SpoofSession
    @EnvironmentObject private var pairing: PairingStore
    @Environment(\.dismiss) private var dismiss

    @State private var placeToRename: SavedPlace?
    @State private var renameText = ""

    var body: some View {
        NavigationStack {
            List {
                Section("Yêu thích") {
                    if session.favorites.isEmpty {
                        Text("Bấm ngôi sao trên bản đồ để lưu ghim.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(session.favorites) { place in
                        placeButton(place)
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button(role: .destructive) {
                                    session.removeFavorite(place)
                                } label: {
                                    Label("Xóa", systemImage: "trash.fill")
                                }
                                Button {
                                    placeToRename = place
                                    renameText = place.name
                                } label: {
                                    Label("Đổi tên", systemImage: "pencil")
                                }
                                .tint(.gray)
                            }
                    }
                }

                Section("Gần đây") {
                    if session.recents.isEmpty {
                        Text("Các lần dịch chuyển sẽ hiện ở đây.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(session.recents) { place in
                        placeButton(place)
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button(role: .destructive) {
                                    session.removeRecent(place)
                                } label: {
                                    Label("Xóa", systemImage: "trash.fill")
                                }
                            }
                    }
                }
            }
            .navigationTitle("Địa điểm")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Xong") { dismiss() }
                }
            }
            .alert("Đổi tên điểm yêu thích", isPresented: Binding(
                get: { placeToRename != nil },
                set: { if !$0 { placeToRename = nil } }
            )) {
                TextField("Tên", text: $renameText)
                Button("Hủy", role: .cancel) {
                    placeToRename = nil
                }
                Button("Lưu") {
                    if let place = placeToRename {
                        session.renameFavorite(place, to: renameText)
                    }
                    placeToRename = nil
                }
            } message: {
                Text("Đặt tên dễ nhớ.")
            }
        }
    }

    private func placeButton(_ place: SavedPlace) -> some View {
        Button {
            // Chỉ chọn điểm; việc dịch chuyển hay di chuyển do người dùng chọn ở thẻ dưới bản đồ.
            session.pointA = nil
            session.pin = place.coordinate
            session.pinName = place.name
            dismiss()
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(place.name).foregroundStyle(.primary)
                Text(String(format: "%.5f, %.5f", place.latitude, place.longitude))
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }
        }
    }
}
