import CoreLocation
import SwiftUI

/// Thẻ dưới bản đồ khi đã chọn điểm. Chạm bản đồ chỉ chọn điểm, không tự dịch chuyển;
/// hành động nằm ở các nút bên dưới.
struct PinActionCard: View {
    @EnvironmentObject private var session: SpoofSession
    @EnvironmentObject private var pairing: PairingStore

    private var title: String {
        if session.pin != nil && session.pointA != nil { return "Từ A đến B" }
        if session.pin != nil { return "Điểm đã chọn" }
        return "Đã đặt điểm A"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.subheadline.weight(.bold))
                    if let a = session.pointA {
                        routeLine(label: "Từ", text: "A · " + Self.coordText(a))
                    } else {
                        routeLine(label: "Từ", text: "Vị trí thật hiện tại")
                    }
                    if let dest = session.routeDestination {
                        routeLine(label: "Đến", text: (session.pin != nil ? "B · " : "A · ") + Self.coordText(dest))
                    }
                }
                Spacer(minLength: 0)
                Button {
                    session.pin = nil
                    session.pinName = nil
                    session.pointA = nil
                } label: {
                    Image(systemName: "xmark")
                        .font(.footnote.weight(.bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 32, height: 32)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Đóng")
            }

            HStack(spacing: 8) {
                actionButton("Dịch chuyển", filled: true) {
                    guard let dest = session.routeDestination else { return }
                    session.pointA = nil
                    session.teleport(to: dest, pairing: pairing)
                }
                .disabled(session.isBusy)

                actionButton("Di chuyển", filled: false) {
                    session.showMoveSheet = true
                }

                if session.pin != nil && session.pointA == nil {
                    actionButton("Đặt làm A", filled: false) {
                        session.pointA = session.pin
                        session.pin = nil
                        session.pinName = nil
                    }
                }
            }

            if session.pointA != nil && session.pin != nil {
                Text("Chạm bản đồ để đổi điểm B. Nút Di chuyển sẽ đi từ A tới B.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else if session.pointA != nil {
                Text("Chạm bản đồ để chọn điểm B. Nếu không chọn B, Dịch chuyển/Di chuyển sẽ đi tới A.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .locusGlass(.regular, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private func routeLine(label: String, text: String) -> some View {
        HStack(spacing: 6) {
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 30, alignment: .leading)
            Text(text)
                .font(.caption.monospaced())
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
    }

    private func actionButton(_ title: String, filled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(filled ? Color.black : Color.primary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 11)
                .background(
                    Capsule().fill(filled ? LocusTheme.accent : Color.primary.opacity(0.10))
                )
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private static func coordText(_ c: CLLocationCoordinate2D) -> String {
        String(format: "%.5f, %.5f", c.latitude, c.longitude)
    }
}
