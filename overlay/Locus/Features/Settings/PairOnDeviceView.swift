import SwiftUI

struct PairOnDeviceView: View {
    enum Mode {
        /// Settings sheet — Close toolbar, dismiss on Done.
        case sheet
        /// First-run setup — no toolbar; calls `onFinished` after success.
        case embedded
    }

    @EnvironmentObject private var pairing: PairingStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase

    @StateObject private var host = PairOnDeviceService()

    var mode: Mode = .sheet
    var onFinished: (() -> Void)?

    var body: some View {
        Group {
            if mode == .sheet {
                NavigationStack {
                    scrollContent
                        .background(Color.black.ignoresSafeArea())
                        .navigationTitle("Ghép nối trên iPhone")
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button("Đóng") {
                                    host.resetToIdle()
                                    dismiss()
                                }
                            }
                        }
                }
            } else {
                scrollContent
            }
        }
        .onChange(of: host.phase) { _, phase in
            if case .succeeded = phase {
                pairing.refresh()
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active, host.isBusy {
                _ = host.pin
            }
        }
    }

    private var scrollContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if mode == .sheet {
                    header
                } else {
                    embeddedIntro
                }

                steps

                statusCard

                if mode == .sheet {
                    tipCard
                }

                actions
            }
            .padding(mode == .embedded ? 16 : 20)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Không cần máy tính")
                .font(.title2.weight(.bold))
            Text("App phát tín hiệu ghép nối. iOS kết nối từ mục Chế độ nhà phát triển, rồi app hiện mã 6 số để bạn nhập.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private var embeddedIntro: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Làm theo các bước sau")
                .font(.headline)
            Text("Để app mở. Bạn sang Cài đặt một lát rồi quay lại lấy mã.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private var steps: some View {
        VStack(alignment: .leading, spacing: 12) {
            step(1, "Tap Start pairing and allow Local Network + Location when asked.")
            step(2, "Cho phép thông báo để mã hiện ngay trên màn hình Cài đặt.")
            step(3, "Mở Cài đặt › Quyền riêng tư & Bảo mật › Chế độ nhà phát triển › Ghép nối với máy chủ (Pair with Host) › chọn Locus › Ghép nối.")
            step(4, "Nhập mật mã mở khóa iPhone trước. Ở ô tiếp theo, nhập mã 6 số app hiện ra.")
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .locusGlass(.regular, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func step(_ n: Int, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(n)")
                .font(.caption.weight(.bold))
                .foregroundStyle(.black)
                .frame(width: 22, height: 22)
                .background(LocusTheme.accent, in: Circle())
            Text(text)
                .font(.subheadline)
                .foregroundStyle(.primary)
        }
    }

    private var tipCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Nếu chưa thấy mã", systemImage: "lightbulb.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(LocusTheme.accentSecondary)
            Text("Không tắt hẳn app trong lúc xác nhận. Nếu mục Locus biến mất, bấm Thử lại rồi mở lại Chế độ nhà phát triển.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(LocusTheme.accentSecondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    @ViewBuilder
    private var statusCard: some View {
        VStack(spacing: 14) {
            switch host.phase {
            case .idle:
                Label("Sẵn sàng", systemImage: "antenna.radiowaves.left.and.right")
                    .foregroundStyle(.secondary)
            case .advertising:
                ProgressView()
                Text("Đang chờ Cài đặt…")
                    .font(.headline)
                Text("Trong Chế độ nhà phát triển, chọn Locus › Ghép nối.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            case .deviceConnected:
                ProgressView()
                Text("iPhone đã kết nối")
                    .font(.headline)
                Text("Đang tạo mã 6 số…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            case .awaitingPIN(let pin):
                Text("Nhập mã này trong Cài đặt")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(pin)
                    .font(.system(size: 48, weight: .bold, design: .rounded))
                    .tracking(10)
                    .monospacedDigit()
                    .foregroundStyle(LocusTheme.accent)
                    .textSelection(.enabled)
                Text("Chỉ nhập ở bước thứ hai, sau mật mã mở khóa.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            case .succeeded:
                Image(systemName: "checkmark.seal.fill")
                    .font(.largeTitle)
                    .foregroundStyle(LocusTheme.statusGood)
                Text("Đã ghép nối")
                    .font(.title3.weight(.bold))
                Text(mode == .embedded
                     ? "Tiếp theo là cài LocalDevVPN."
                     : "Đã lưu file RPPairing. Bật LocalDevVPN rồi dịch chuyển.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            case .failed(let message):
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.largeTitle)
                    .foregroundStyle(LocusTheme.statusWarn)
                Text("Ghép nối thất bại")
                    .font(.title3.weight(.bold))
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(24)
        .locusGlass(.regular, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    @ViewBuilder
    private var actions: some View {
        switch host.phase {
        case .idle, .failed:
            Button {
                host.acknowledgeFailure()
                host.start(pairingStore: pairing)
            } label: {
                Text(host.phase == .idle ? "Bắt đầu ghép nối" : "Thử lại")
                    .font(.headline)
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Capsule().fill(LocusTheme.accent))
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
        case .succeeded:
            Button {
                if let onFinished {
                    onFinished()
                } else {
                    dismiss()
                }
            } label: {
                Text(mode == .embedded ? "Tiếp tục" : "Xong")
                    .font(.headline)
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Capsule().fill(LocusTheme.accent))
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
        case .advertising, .deviceConnected, .awaitingPIN:
            Text({
                switch host.phase {
                case .awaitingPIN: return "Nhập mã trên vào ô thứ hai trong Cài đặt."
                case .deviceConnected: return "Đã kết nối, mã sắp hiện."
                default: return "Đang chờ iOS kết nối… đừng tắt hẳn app."
                }
            }())
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .multilineTextAlignment(.center)
        }
    }
}
