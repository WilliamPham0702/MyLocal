import MapKit
import SwiftUI

struct MapHomeView: View {
    @EnvironmentObject private var session: SpoofSession
    @EnvironmentObject private var pairing: PairingStore

    @StateObject private var search = PlaceSearchCompleter()
    @State private var position: MapCameraPosition = .userLocation(fallback: .automatic)
    @State private var searchText = ""
    @FocusState private var searchFocused: Bool
    @State private var routeStart: CLLocationCoordinate2D?
    @State private var routeEnd: CLLocationCoordinate2D?
    @State private var routeCoords: [CLLocationCoordinate2D] = []
    @State private var isRouting = false
    @State private var showRouteSheet = false
    @State private var showGPXImporter = false
    @State private var drawnPath: [CLLocationCoordinate2D] = []
    @State private var drawMode = false
    @State private var pinSelected = false
    @State private var isDraggingPin = false
    @State private var suppressNextMapTap = false
    /// Set when the pin comes from search / a named place so starring keeps the title.
    @State private var pinPlaceName: String?
    /// Mũi tên đỏ: vị trí tạm khi đang kéo.
    @State private var arrowDragCoordinate: CLLocationCoordinate2D?
    @State private var isDraggingArrow = false
    /// Đang chấm điểm đường thủ công (chạm bản đồ để thêm điểm).
    @State private var manualRouteActive = false
    @State private var moveStyle: MoveDrawStyle = .auto

    private var mapStyle: MapStyle {
        switch session.mapStyleIndex {
        case 1: return .hybrid(elevation: .realistic)
        case 2: return .imagery(elevation: .realistic)
        // Mặc định: bản đồ đường phố phẳng, nền tối, có địa điểm — giống Google Maps.
        default: return .standard(elevation: .flat, pointsOfInterest: .all, showsTraffic: false)
        }
    }

    var body: some View {
        ZStack(alignment: .top) {
            // Keep Map inside the safe layout bounds so MapProxy.convert matches
            // finger position. Ignoring the safe area makes the tiles full-bleed but
            // shifts convert() upward by ~status-bar height.
            MapReader { proxy in
                Map(position: $position, interactionModes: [.pan, .zoom, .rotate]) {
                    if let here = arrowDragCoordinate ?? session.simulated ?? session.liveCoordinate {
                        Annotation("", coordinate: here, anchor: .center) {
                            RedArrowMarker(
                                heading: session.heading,
                                isDragging: isDraggingArrow,
                                onDragBegan: {
                                    searchFocused = false
                                    suppressNextMapTap = true
                                    isDraggingArrow = true
                                    session.stopJoystick()
                                },
                                onDragMoved: { globalPoint in
                                    if let coord = proxy.convert(globalPoint, from: .global) {
                                        arrowDragCoordinate = coord
                                    }
                                },
                                onDragEnded: {
                                    isDraggingArrow = false
                                    if let dest = arrowDragCoordinate {
                                        // Chỉ ghim điểm đến; không tự dịch chuyển.
                                        session.pin = dest
                                        pinPlaceName = nil
                                        session.pinName = nil
                                    }
                                    arrowDragCoordinate = nil
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                                        suppressNextMapTap = false
                                    }
                                }
                            )
                        }
                    }

                    if let a = session.pointA {
                        Annotation("", coordinate: a, anchor: .center) {
                            Text("A")
                                .font(.caption.weight(.heavy))
                                .foregroundStyle(.white)
                                .frame(width: 26, height: 26)
                                .background(Circle().fill(LocusTheme.accentSecondary))
                                .shadow(color: .black.opacity(0.35), radius: 3, y: 1)
                        }
                    }

                    if let pin = session.pin {
                        Annotation("", coordinate: pin, anchor: .bottom) {
                            MapDropPin(
                                selected: pinSelected,
                                isDragging: isDraggingPin,
                                onSelect: {
                                    searchFocused = false
                                    suppressNextMapTap = true
                                    withAnimation(.spring(response: 0.28, dampingFraction: 0.78)) {
                                        pinSelected.toggle()
                                    }
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                                        suppressNextMapTap = false
                                    }
                                },
                                onRemove: {
                                    suppressNextMapTap = true
                                    withAnimation {
                                        session.pin = nil
                                        pinSelected = false
                                    }
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                                        suppressNextMapTap = false
                                    }
                                },
                                onDragBegan: {
                                    searchFocused = false
                                    suppressNextMapTap = true
                                    pinSelected = false
                                    isDraggingPin = true
                                },
                                onDragMoved: { globalPoint in
                                    if let coord = proxy.convert(globalPoint, from: .global) {
                                        session.pin = coord
                                    }
                                },
                                onDragEnded: {
                                    isDraggingPin = false
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                                        suppressNextMapTap = false
                                    }
                                }
                            )
                        }
                    }
                    if routeCoords.count > 1 {
                        MapPolyline(coordinates: routeCoords)
                            .stroke(LocusTheme.accent, lineWidth: 5)
                    }
                    if drawnPath.count > 1 {
                        MapPolyline(coordinates: drawnPath)
                            .stroke(LocusTheme.accentSecondary, style: StrokeStyle(lineWidth: 4, dash: [6, 4]))
                    }
                }
                .mapStyle(mapStyle)
                .mapControlVisibility(.hidden)
                .onTapGesture { point in
                    searchFocused = false
                    guard !suppressNextMapTap, !isDraggingPin else { return }
                    pinSelected = false
                    placePin(at: point, proxy: proxy)
                }
            }
            .background(Color.black.ignoresSafeArea())

            topChrome
        }
        .onAppear {
            session.startLocationUpdates()
        }
        .onChange(of: session.pin?.latitude) { _, newValue in
            if newValue == nil { pinSelected = false }
            // Đổi điểm đến thì bỏ đường cũ (trừ lúc đang tự đi theo đường).
            if !session.isFollowingRoute { routeCoords = [] }
        }
        .onReceive(NotificationCenter.default.publisher(for: .locusImportGPX)) { note in
            guard let url = note.object as? URL else { return }
            importGPX(url)
        }
        .fileImporter(isPresented: $showGPXImporter, allowedContentTypes: [.xml, .data], allowsMultipleSelection: false) { result in
            if case .success(let urls) = result, let url = urls.first {
                importGPX(url)
            }
        }
        .sheet(isPresented: $session.showMoveSheet) {
            if let dest = session.routeDestination {
                MoveSheet(
                    origin: session.routeOrigin,
                    destination: dest,
                    routePreview: routeCoords,
                    style: $moveStyle,
                    isRouting: $isRouting,
                    onBuildAuto: buildAutoRoute,
                    onStartManual: {
                        session.showMoveSheet = false
                        beginManualRoute()
                    },
                    onGo: { startMove(routeCoords) }
                )
                .presentationDetents([.medium, .large])
            }
        }
        .sheet(isPresented: $showRouteSheet) {
            RoutePlannerSheet(
                start: $routeStart,
                end: $routeEnd,
                isRouting: $isRouting,
                onBuild: buildRoadRoute,
                onPlay: playRoute,
                onImportGPX: { showGPXImporter = true },
                onExportGPX: exportGPX,
                onUseDrawn: {
                    routeCoords = RouteBuilder.sample(coordinates: drawnPath, every: 10)
                    drawnPath.removeAll()
                    drawMode = false
                }
            )
            .presentationDetents([.medium, .large])
        }
    }

    private func placePin(at point: CGPoint, proxy: MapProxy) {
        guard let coord = proxy.convert(point, from: .local) else { return }
        if drawMode {
            drawnPath.append(coord)
        } else {
            session.pin = coord
            pinPlaceName = nil
            session.pinName = nil
            pinSelected = false
        }
    }

    private var topChrome: some View {
        VStack(spacing: 10) {
            StatusBarView()

            searchBar

            if manualRouteActive {
                manualBar
            }

            if let coord = Self.parseCoordinate(searchText) {
                coordinateResult(coord)
            } else if !searchText.isEmpty && !search.results.isEmpty {
                searchResults
            }

            HStack(alignment: .center, spacing: 10) {
                mapChromeButtons
                Spacer(minLength: 0)
                locateButton
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 2)
        .safeAreaPadding(.top, 8)
    }

    /// Thanh hiện khi đang chấm đường thủ công.
    private var manualBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "pencil.tip")
                .foregroundStyle(LocusTheme.accentSecondary)
            Text("Chạm bản đồ để thêm điểm (\(drawnPath.count))")
                .font(.subheadline.weight(.semibold))
            Spacer(minLength: 0)
            Button("Hủy") {
                cancelManualRoute()
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            Button("Bắt đầu") {
                finishManualRoute()
            }
            .font(.subheadline.weight(.bold))
            .buttonStyle(.plain)
            .foregroundStyle(LocusTheme.accent)
        }
        .padding(12)
        .locusGlass(.regular, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var searchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Tìm địa chỉ hoặc nhập tọa độ", text: $searchText)
                .textInputAutocapitalization(.words)
                .focused($searchFocused)
                .submitLabel(.search)
                .onSubmit {
                    if let coord = Self.parseCoordinate(searchText) {
                        goTo(coordinate: coord)
                    } else {
                        searchFocused = false
                    }
                }
                .onChange(of: searchText) { _, value in
                    search.query = value
                }
            if searchFocused || !searchText.isEmpty {
                Button {
                    searchText = ""
                    search.query = ""
                    searchFocused = false
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Xóa và ẩn bàn phím")
            }
            if searchFocused {
                Button("Xong") {
                    searchFocused = false
                }
                .font(.subheadline.weight(.semibold))
                .buttonStyle(.plain)
                .foregroundStyle(LocusTheme.accent)
            }
        }
        .padding(12)
        .locusGlass(.regular, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var searchResults: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(search.results.prefix(5), id: \.self) { item in
                Button {
                    select(completion: item)
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.title).font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
                        if !item.subtitle.isEmpty {
                            Text(item.subtitle).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                Divider().opacity(0.3)
            }
        }
        .locusGlass(.regular, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var mapChromeButtons: some View {
        HStack(spacing: 4) {
            chromeIconButton("square.3.layers.3d") {
                session.mapStyleIndex = (session.mapStyleIndex + 1) % 3
            }
            chromeIconButton("point.topleft.down.to.point.bottomright.curvepath") {
                showRouteSheet = true
            }
            chromeIconButton(drawMode ? "pencil.tip.crop.circle.badge.minus" : "pencil.tip.crop.circle") {
                drawMode.toggle()
                if !drawMode { drawnPath.removeAll() }
            }
            .foregroundStyle(drawMode ? LocusTheme.accentSecondary : .primary)

            if session.pin != nil {
                chromeIconButton("star.circle") {
                    if let pin = session.pin {
                        let name = session.suggestedFavoriteName(for: pin, fallback: pinPlaceName)
                        session.addFavorite(name: name, coordinate: pin)
                    }
                }
            }
        }
        .padding(6)
        .locusGlass(.clear, in: Capsule())
        .contentShape(Capsule())
    }

    private var locateButton: some View {
        Button {
            searchFocused = false
            goToCurrentLocation()
        } label: {
            Image(systemName: "location.fill")
                .font(.body.weight(.semibold))
                .frame(width: 48, height: 48)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .locusGlass(.interactive, in: Circle())
        .foregroundStyle(.primary)
        .contentShape(Circle())
        .accessibilityLabel("Vị trí hiện tại")
    }

    /// Centers on the spoofed fix while spoofing, otherwise the real GPS —
    /// never the leftover teleport pin (`.automatic` would frame that marker).
    private func goToCurrentLocation() {
        let meters: CLLocationDistance = 900
        withAnimation(.easeInOut(duration: 0.35)) {
            if session.isSpoofing, let sim = session.simulated {
                position = .region(MKCoordinateRegion(
                    center: sim,
                    latitudinalMeters: meters,
                    longitudinalMeters: meters
                ))
            } else if let real = session.realCoordinate {
                position = .region(MKCoordinateRegion(
                    center: real,
                    latitudinalMeters: meters,
                    longitudinalMeters: meters
                ))
            } else {
                position = .userLocation(
                    followsHeading: false,
                    fallback: .region(MKCoordinateRegion(
                        center: CLLocationCoordinate2D(latitude: 37.3349, longitude: -122.0090),
                        latitudinalMeters: 2000,
                        longitudinalMeters: 2000
                    ))
                )
            }
        }
    }

    private func chromeIconButton(_ systemName: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.body.weight(.semibold))
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.primary)
    }

    /// Nhận "10.7769, 106.7009" hoặc "10.7769 106.7009" (vĩ độ trước, kinh độ sau).
    static func parseCoordinate(_ text: String) -> CLLocationCoordinate2D? {
        let parts = text
            .replacingOccurrences(of: ";", with: ",")
            .split(whereSeparator: { $0 == "," || $0 == " " })
            .map { String($0) }
            .filter { !$0.isEmpty }
        guard parts.count == 2,
              let lat = Double(parts[0]),
              let lon = Double(parts[1]),
              (-90.0...90.0).contains(lat),
              (-180.0...180.0).contains(lon) else { return nil }
        return CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }

    private func coordinateResult(_ coord: CLLocationCoordinate2D) -> some View {
        Button {
            goTo(coordinate: coord)
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text("Đi tới tọa độ")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                Text(String(format: "%.6f, %.6f", coord.latitude, coord.longitude))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .locusGlass(.regular, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func goTo(coordinate coord: CLLocationCoordinate2D) {
        session.pin = coord
        pinPlaceName = nil
        session.pinName = nil
        pinSelected = false
        position = .region(MKCoordinateRegion(center: coord, latitudinalMeters: 1200, longitudinalMeters: 1200))
        searchText = ""
        search.query = ""
        searchFocused = false
    }

    private func select(completion: MKLocalSearchCompletion) {
        Task {
            let request = MKLocalSearch.Request(completion: completion)
            if let response = try? await MKLocalSearch(request: request).start(),
               let item = response.mapItems.first {
                let coord = item.placemark.coordinate
                let title = item.name ?? completion.title
                await MainActor.run {
                    session.pin = coord
                    pinPlaceName = title
                    session.pinName = title
                    position = .region(MKCoordinateRegion(center: coord, latitudinalMeters: 1200, longitudinalMeters: 1200))
                    searchText = ""
                    search.query = ""
                    searchFocused = false
                    session.pushNamedRecent(name: title, coordinate: coord)
                }
            }
        }
    }

    /// Tự tính đường theo phố từ điểm xuất phát (A hoặc vị trí thật) tới đích (B hoặc A).
    private func buildAutoRoute() {
        guard let end = session.routeDestination else {
            session.lastError = "Hãy chạm bản đồ để chọn điểm đến."
            return
        }
        guard let start = session.routeOrigin ?? session.realCoordinate else {
            session.lastError = "Chưa có vị trí thật để xuất phát. Hãy bật định vị hoặc đặt điểm A."
            return
        }
        isRouting = true
        Task {
            do {
                let coords = try await RouteBuilder.roadRoute(from: start, to: end, mode: session.travelMode)
                await MainActor.run {
                    routeCoords = coords
                    isRouting = false
                }
            } catch {
                await MainActor.run {
                    isRouting = false
                    session.lastError = error.localizedDescription
                }
            }
        }
    }

    /// Bắt đầu chấm đường thủ công: đường sẽ là xuất phát → các điểm chạm → đích.
    private func beginManualRoute() {
        guard session.routeDestination != nil else {
            session.lastError = "Hãy chạm bản đồ để chọn điểm đến."
            return
        }
        drawnPath.removeAll()
        drawMode = true
        manualRouteActive = true
    }

    private func finishManualRoute() {
        guard let end = session.routeDestination else { return }
        guard let start = session.routeOrigin ?? session.realCoordinate else {
            session.lastError = "Chưa có vị trí thật để xuất phát. Hãy bật định vị hoặc đặt điểm A."
            return
        }
        let path = [start] + drawnPath + [end]
        manualRouteActive = false
        drawMode = false
        startMove(path)
    }

    private func cancelManualRoute() {
        manualRouteActive = false
        drawMode = false
        drawnPath.removeAll()
    }

    /// Đi theo đường đã có. Điểm A (nếu có) được dùng xong thì xóa.
    private func startMove(_ path: [CLLocationCoordinate2D]) {
        guard pairing.hasPairingFile else {
            session.lastError = "Hãy nhập file pairing trong Cài đặt trước."
            return
        }
        guard path.count >= 2 else {
            session.lastError = "Hãy tạo hoặc vẽ đường đi trước."
            return
        }
        routeCoords = path
        drawnPath.removeAll()
        session.pointA = nil
        session.showMoveSheet = false
        session.followRoute(path, pairing: pairing)
    }

    private func buildRoadRoute() {
        guard let start = routeStart ?? session.simulated ?? session.pin,
              let end = routeEnd else {
            session.lastError = "Hãy chọn điểm đầu và điểm cuối."
            return
        }
        isRouting = true
        Task {
            do {
                let coords = try await RouteBuilder.roadRoute(from: start, to: end, mode: session.travelMode)
                await MainActor.run {
                    routeCoords = coords
                    isRouting = false
                }
            } catch {
                await MainActor.run {
                    isRouting = false
                    session.lastError = error.localizedDescription
                }
            }
        }
    }

    private func playRoute() {
        let path = routeCoords.isEmpty ? drawnPath : routeCoords
        guard path.count >= 2 else {
            session.lastError = "Hãy tạo hoặc vẽ đường đi trước."
            return
        }
        showRouteSheet = false
        session.followRoute(path, pairing: pairing)
    }

    private func importGPX(_ url: URL) {
        do {
            let coords = try GPXCodec.parse(url)
            routeCoords = RouteBuilder.sample(coordinates: coords, every: 10)
            if let first = coords.first {
                session.pin = first
                position = .region(MKCoordinateRegion(center: first, latitudinalMeters: 2000, longitudinalMeters: 2000))
            }
        } catch {
            session.lastError = error.localizedDescription
        }
    }

    private func exportGPX() {
        let path = routeCoords.isEmpty ? drawnPath : routeCoords
        guard !path.isEmpty else {
            session.lastError = "Không có gì để xuất."
            return
        }
        let gpx = GPXCodec.export(path)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("Locus-Route.gpx")
        do {
            try gpx.data(using: .utf8)?.write(to: url)
            let av = UIActivityViewController(activityItems: [url], applicationActivities: nil)
            if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
               let root = scene.keyWindow?.rootViewController {
                root.present(av, animated: true)
            }
        } catch {
            session.lastError = error.localizedDescription
        }
    }
}

private extension UIWindowScene {
    var keyWindow: UIWindow? { windows.first { $0.isKeyWindow } }
}

@MainActor
final class PlaceSearchCompleter: NSObject, ObservableObject, MKLocalSearchCompleterDelegate {
    @Published var results: [MKLocalSearchCompletion] = []
    private let completer = MKLocalSearchCompleter()

    var query: String = "" {
        didSet {
            completer.queryFragment = query
        }
    }

    override init() {
        super.init()
        completer.delegate = self
        completer.resultTypes = [.address, .pointOfInterest]
    }

    nonisolated func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        let items = completer.results
        Task { @MainActor in self.results = items }
    }

    nonisolated func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        Task { @MainActor in self.results = [] }
    }
}
