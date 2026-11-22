import CoreLocation
import SwiftUI

struct RoutePlannerSheet: View {
    @Binding var start: CLLocationCoordinate2D?
    @Binding var end: CLLocationCoordinate2D?
    @Binding var isRouting: Bool
    var onBuild: () -> Void
    var onPlay: () -> Void
    var onImportGPX: () -> Void
    var onExportGPX: () -> Void
    var onUseDrawn: () -> Void

    @EnvironmentObject private var session: SpoofSession
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("Đường đi theo đường phố") {
                    Button("Dùng ghim / vị trí giả hiện tại làm điểm đầu") {
                        start = session.simulated ?? session.pin
                    }
                    Button("Dùng ghim hiện tại làm điểm cuối") {
                        end = session.pin
                    }
                    LabeledContent("Điểm đầu") {
                        Text(coordText(start)).font(.caption.monospaced())
                    }
                    LabeledContent("Điểm cuối") {
                        Text(coordText(end)).font(.caption.monospaced())
                    }
                    Button {
                        onBuild()
                    } label: {
                        if isRouting {
                            ProgressView()
                        } else {
                            Label("Tạo đường đi bộ/lái xe theo đường phố", systemImage: "road.lanes")
                        }
                    }
                    .disabled(isRouting)
                }

                Section("Chạy / vẽ / GPX") {
                    Button {
                        onUseDrawn()
                    } label: {
                        Label("Dùng đường đã vẽ trên bản đồ", systemImage: "pencil.tip")
                    }
                    Button(action: onPlay) {
                        Label("Chạy theo đường đi", systemImage: "play.fill")
                    }
                    Button(action: onImportGPX) {
                        Label("Nhập GPX", systemImage: "square.and.arrow.down")
                    }
                    Button(action: onExportGPX) {
                        Label("Xuất GPX", systemImage: "square.and.arrow.up")
                    }
                }

                Section {
                    Text("Đường đi bám theo đường phố/lối đi của Apple Maps theo kiểu di chuyển đã chọn. Tốc độ dao động nhẹ để chuyển động tự nhiên hơn.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Đường đi")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Xong") { dismiss() }
                }
            }
        }
    }

    private func coordText(_ c: CLLocationCoordinate2D?) -> String {
        guard let c else { return "—" }
        return String(format: "%.5f, %.5f", c.latitude, c.longitude)
    }
}
