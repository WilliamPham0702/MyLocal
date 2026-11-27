import CoreLocation
import SwiftUI

/// Cách vẽ đường: app tự tính theo đường phố, hoặc người dùng tự chấm điểm trên bản đồ.
enum MoveDrawStyle: String, CaseIterable, Identifiable {
    case auto, manual

    var id: String { rawValue }

    var title: String {
        switch self {
        case .auto: return "Tự động"
        case .manual: return "Thủ công"
        }
    }
}

/// Bảng "Di chuyển": hiển thị A → B, chọn cách vẽ và phương tiện.
struct MoveSheet: View {
    @EnvironmentObject private var session: SpoofSession
    @Environment(\.dismiss) private var dismiss

    /// Điểm A nếu đã đặt; nil nghĩa là xuất phát từ vị trí thật hiện tại.
    let origin: CLLocationCoordinate2D?
    let destination: CLLocationCoordinate2D
    let routePreview: [CLLocationCoordinate2D]
    @Binding var style: MoveDrawStyle
    @Binding var isRouting: Bool
    var onBuildAuto: () -> Void
    var onStartManual: () -> Void
    var onGo: () -> Void

    var body: some View {
        NavigationStack {
            List {
                Section("Lộ trình") {
                    LabeledContent("Điểm đầu") {
                        Text(origin.map { Self.coordText($0) } ?? "Vị trí thật hiện tại")
                            .font(.caption.monospaced())
                    }
                    LabeledContent("Điểm đến") {
                        Text(Self.coordText(destination))
                            .font(.caption.monospaced())
                    }
                }

                Section("Cách vẽ đường") {
                    Picker("Cách vẽ", selection: $style) {
                        ForEach(MoveDrawStyle.allCases) { item in
                            Text(item.title).tag(item)
                        }
                    }
                    .pickerStyle(.segmented)

                    if style == .auto {
                        Button {
                            onBuildAuto()
                        } label: {
                            if isRouting {
                                ProgressView()
                            } else {
                                Label("Tạo đường theo phố", systemImage: "road.lanes")
                            }
                        }
                        .disabled(isRouting)

                        if routePreview.count > 1 {
                            Label("Đã có đường đi (\(routePreview.count) điểm)", systemImage: "checkmark.circle")
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        Text("Đóng bảng rồi chạm bản đồ để thêm điểm trung gian. Khi xong, bấm Bắt đầu trên thanh phía trên.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        Button {
                            onStartManual()
                        } label: {
                            Label("Bắt đầu vẽ thủ công", systemImage: "pencil.tip")
                        }
                    }
                }

                Section("Phương tiện") {
                    ForEach(TravelMode.allCases) { mode in
                        Button {
                            session.travelMode = mode
                        } label: {
                            HStack {
                                Label(mode.title, systemImage: mode.icon)
                                Spacer()
                                if session.travelMode == mode {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(LocusTheme.accent)
                                }
                            }
                        }
                        .foregroundStyle(.primary)
                    }
                }

                if style == .auto {
                    Section {
                        Button {
                            onGo()
                        } label: {
                            Label("Bắt đầu di chuyển", systemImage: "play.fill")
                        }
                        .disabled(routePreview.count < 2)
                    }
                }
            }
            .navigationTitle("Di chuyển")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Đóng") { dismiss() }
                }
            }
        }
    }

    private static func coordText(_ c: CLLocationCoordinate2D) -> String {
        String(format: "%.5f, %.5f", c.latitude, c.longitude)
    }
}
