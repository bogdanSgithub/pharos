//
//  TripReportView.swift
//  mchacks
//
//  Clean trip analysis with map, stats, and PERCLOS graph
//

import SwiftUI
import MapboxMaps
import CoreLocation
import Turf

struct TripReportView: View {
    @Binding var isPresented: Bool

    let tripDuration: TimeInterval
    let tripDistance: String
    let alertCount: Int
    let phonePickupCount: Int
    let yawnCount: Int
    let baselineBlinkRate: Float
    let averageBlinkRate: Float
    let perclosHistory: [Float]
    let routeCoordinates: [CLLocationCoordinate2D]

    @State private var appeared = false

    // MARK: - Computed Properties

    private var formattedDuration: String {
        let hours = Int(tripDuration) / 3600
        let minutes = Int(tripDuration) / 60 % 60
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else {
            return "\(minutes) min"
        }
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 16) {

                    // MARK: - Route Map
                    RouteMapView(coordinates: routeCoordinates)
                        .frame(height: 200)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .padding(.horizontal, 16)

                    // MARK: - Stats Grid
                    LazyVGrid(columns: [
                        GridItem(.flexible(), spacing: 12),
                        GridItem(.flexible(), spacing: 12)
                    ], spacing: 12) {

                        StatCard(
                            icon: "clock",
                            value: formattedDuration,
                            label: "Duration"
                        )

                        StatCard(
                            icon: "arrow.right",
                            value: tripDistance,
                            label: "Distance"
                        )

                        StatCard(
                            icon: "exclamationmark.triangle",
                            value: "\(alertCount)",
                            label: "Alerts",
                            valueColor: alertCount > 0 ? Color(hex: "EF4444") : nil
                        )

                        StatCard(
                            icon: "iphone",
                            value: "\(phonePickupCount)",
                            label: "Phone Pickups",
                            valueColor: phonePickupCount > 0 ? Color(hex: "F97316") : nil
                        )

                        StatCard(
                            icon: "mouth",
                            value: "\(yawnCount)",
                            label: "Yawns",
                            valueColor: yawnCount >= 3 ? Color(hex: "EAB308") : nil
                        )

                        BlinkRateCard(
                            baseline: baselineBlinkRate,
                            average: averageBlinkRate
                        )
                    }
                    .padding(.horizontal, 16)

                    // MARK: - PERCLOS Graph
                    if !perclosHistory.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("PERCLOS")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(Color(hex: "9CA3AF"))
                                .padding(.horizontal, 4)

                            PerclosGraphView(data: perclosHistory, tripDuration: tripDuration)
                                .frame(height: 140)
                        }
                        .padding(16)
                        .background(Color(hex: "111827"))
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .padding(.horizontal, 16)
                    }

                    Spacer().frame(height: 80)
                }
                .padding(.top, 16)
            }
            .background(Color(hex: "030712"))
            .navigationTitle("Trip Summary")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color(hex: "030712"), for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: { isPresented = false }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(Color(hex: "9CA3AF"))
                    }
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    ShareLink(
                        item: generateShareText(),
                        subject: Text("Trip Summary"),
                        message: Text("")
                    ) {
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(Color(hex: "9CA3AF"))
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                Button(action: { isPresented = false }) {
                    Text("Done")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(Color(hex: "1F2937"))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
                .background(Color(hex: "030712"))
            }
        }
        .onAppear {
            appeared = true
        }
    }

    private func generateShareText() -> String {
        """
        Trip Summary

        Duration: \(formattedDuration)
        Distance: \(tripDistance)
        Alerts: \(alertCount)
        Phone Pickups: \(phonePickupCount)
        Yawns: \(yawnCount)
        Blink Rate: \(Int(averageBlinkRate)) avg / \(Int(baselineBlinkRate)) baseline per min
        """
    }
}

// MARK: - Stat Card

struct StatCard: View {
    let icon: String
    let value: String
    let label: String
    var valueColor: Color? = nil

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 18))
                .foregroundColor(Color(hex: "6B7280"))

            Text(value)
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundColor(valueColor ?? .white)

            Text(label)
                .font(.system(size: 12))
                .foregroundColor(Color(hex: "6B7280"))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .background(Color(hex: "111827"))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Blink Rate Card (special layout for clarity)

struct BlinkRateCard: View {
    let baseline: Float
    let average: Float

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "eye")
                .font(.system(size: 18))
                .foregroundColor(Color(hex: "6B7280"))

            HStack(spacing: 12) {
                VStack(spacing: 2) {
                    Text("\(Int(average))")
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                    Text("avg")
                        .font(.system(size: 10))
                        .foregroundColor(Color(hex: "6B7280"))
                }

                Text("/")
                    .font(.system(size: 16))
                    .foregroundColor(Color(hex: "4B5563"))

                VStack(spacing: 2) {
                    Text("\(Int(baseline))")
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundColor(Color(hex: "9CA3AF"))
                    Text("baseline")
                        .font(.system(size: 10))
                        .foregroundColor(Color(hex: "6B7280"))
                }
            }

            Text("Blinks/min")
                .font(.system(size: 12))
                .foregroundColor(Color(hex: "6B7280"))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .background(Color(hex: "111827"))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Route Map View (Mapbox)

struct RouteMapView: View {
    let coordinates: [CLLocationCoordinate2D]

    var body: some View {
        if coordinates.count >= 2 {
            StaticMapboxRouteView(coordinates: coordinates)
        } else {
            // Fallback when no route data
            ZStack {
                Color(hex: "1F2937")
                VStack(spacing: 8) {
                    Image(systemName: "map")
                        .font(.system(size: 32))
                        .foregroundColor(Color(hex: "4B5563"))
                    Text("Route not available")
                        .font(.system(size: 13))
                        .foregroundColor(Color(hex: "6B7280"))
                }
            }
        }
    }
}

// MARK: - Static Mapbox Route View

struct StaticMapboxRouteView: UIViewRepresentable {
    let coordinates: [CLLocationCoordinate2D]

    func makeUIView(context: Context) -> MapView {
        let mapInitOptions = MapInitOptions(
            cameraOptions: CameraOptions(zoom: 12),
            styleURI: .streets
        )

        let mapView = MapView(frame: .zero, mapInitOptions: mapInitOptions)
        mapView.autoresizingMask = [.flexibleWidth, .flexibleHeight]

        // Disable all interactions for static display
        mapView.gestures.options.panEnabled = false
        mapView.gestures.options.pinchEnabled = false
        mapView.gestures.options.rotateEnabled = false
        mapView.gestures.options.pitchEnabled = false
        mapView.gestures.options.doubleTapToZoomInEnabled = false
        mapView.gestures.options.doubleTouchToZoomOutEnabled = false
        mapView.gestures.options.quickZoomEnabled = false

        // Hide ornaments
        mapView.ornaments.options.scaleBar.visibility = .hidden
        mapView.ornaments.options.compass.visibility = .hidden
        mapView.ornaments.options.logo.margins = CGPoint(x: 8, y: 8)
        mapView.ornaments.options.attributionButton.margins = CGPoint(x: 8, y: 8)

        // Hide location puck
        mapView.location.options.puckType = nil

        context.coordinator.mapView = mapView
        context.coordinator.setupRoute()

        return mapView
    }

    func updateUIView(_ uiView: MapView, context: Context) {
        // Static view, no updates needed
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(coordinates: coordinates)
    }

    class Coordinator {
        weak var mapView: MapView?
        let coordinates: [CLLocationCoordinate2D]
        private var didSetupRoute = false

        init(coordinates: [CLLocationCoordinate2D]) {
            self.coordinates = coordinates
        }

        func setupRoute() {
            guard let mapView = mapView, !didSetupRoute, coordinates.count >= 2 else { return }

            // Add route after a short delay to ensure map style is loaded
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                self?.addRouteAndMarkers()
            }
        }

        private func addRouteAndMarkers() {
            guard let mapView = mapView, !didSetupRoute else { return }
            didSetupRoute = true

            let routeSourceId = "trip-route-source"
            let routeLayerId = "trip-route-layer"
            let startSourceId = "trip-start-source"
            let startLayerId = "trip-start-layer"
            let endSourceId = "trip-end-source"
            let endLayerId = "trip-end-layer"

            // Add route line
            var routeSource = GeoJSONSource(id: routeSourceId)
            routeSource.data = .geometry(.lineString(LineString(coordinates)))
            try? mapView.mapboxMap.addSource(routeSource)

            var routeLayer = LineLayer(id: routeLayerId, source: routeSourceId)
            routeLayer.lineColor = .constant(StyleColor(UIColor(red: 0.231, green: 0.510, blue: 0.965, alpha: 1.0))) // #3B82F6
            routeLayer.lineWidth = .constant(5)
            routeLayer.lineCap = .constant(.round)
            routeLayer.lineJoin = .constant(.round)
            try? mapView.mapboxMap.addLayer(routeLayer)

            // Add start marker (green circle)
            if let startCoord = coordinates.first {
                var startSource = GeoJSONSource(id: startSourceId)
                startSource.data = .geometry(.point(Point(startCoord)))
                try? mapView.mapboxMap.addSource(startSource)

                var startLayer = CircleLayer(id: startLayerId, source: startSourceId)
                startLayer.circleRadius = .constant(8)
                startLayer.circleColor = .constant(StyleColor(UIColor(red: 0.133, green: 0.773, blue: 0.369, alpha: 1.0))) // #22C55E
                startLayer.circleStrokeWidth = .constant(3)
                startLayer.circleStrokeColor = .constant(StyleColor(.white))
                try? mapView.mapboxMap.addLayer(startLayer)
            }

            // Add end marker (red circle)
            if let endCoord = coordinates.last {
                var endSource = GeoJSONSource(id: endSourceId)
                endSource.data = .geometry(.point(Point(endCoord)))
                try? mapView.mapboxMap.addSource(endSource)

                var endLayer = CircleLayer(id: endLayerId, source: endSourceId)
                endLayer.circleRadius = .constant(8)
                endLayer.circleColor = .constant(StyleColor(UIColor(red: 0.937, green: 0.267, blue: 0.267, alpha: 1.0))) // #EF4444
                endLayer.circleStrokeWidth = .constant(3)
                endLayer.circleStrokeColor = .constant(StyleColor(.white))
                try? mapView.mapboxMap.addLayer(endLayer)
            }

            // Fit camera to show entire route
            let cameraOptions = mapView.mapboxMap.camera(
                for: .lineString(LineString(coordinates)),
                padding: UIEdgeInsets(top: 30, left: 30, bottom: 30, right: 30),
                bearing: nil,
                pitch: nil
            )
            mapView.camera.ease(to: cameraOptions, duration: 0.5)
        }
    }
}

// MARK: - PERCLOS Graph View

struct PerclosGraphView: View {
    let data: [Float]
    let tripDuration: TimeInterval

    private var maxValue: Float {
        max(data.max() ?? 10, 10)  // At least 10% scale
    }

    private func formatTime(_ seconds: TimeInterval) -> String {
        let mins = Int(seconds) / 60
        if mins < 60 {
            return "\(mins)m"
        } else {
            let hrs = mins / 60
            let remainingMins = mins % 60
            return "\(hrs)h\(remainingMins)m"
        }
    }

    var body: some View {
        VStack(spacing: 4) {
            // Graph area
            GeometryReader { geo in
                let width = geo.size.width - 40  // Leave space for Y-axis
                let height = geo.size.height
                let stepX = data.count > 1 ? width / CGFloat(data.count - 1) : width

                ZStack(alignment: .topLeading) {
                    // Y-axis labels
                    VStack {
                        Text("\(Int(maxValue))%")
                            .font(.system(size: 9))
                            .foregroundColor(Color(hex: "6B7280"))
                        Spacer()
                        Text("0%")
                            .font(.system(size: 9))
                            .foregroundColor(Color(hex: "6B7280"))
                    }
                    .frame(width: 35)

                    // Graph content
                    ZStack {
                        // Grid lines
                        VStack(spacing: 0) {
                            ForEach(0..<4) { i in
                                Rectangle()
                                    .fill(Color(hex: "374151"))
                                    .frame(height: 1)
                                if i < 3 {
                                    Spacer()
                                }
                            }
                        }

                        // Fill under the line
                        Path { path in
                            path.move(to: CGPoint(x: 0, y: height))

                            for (index, value) in data.enumerated() {
                                let x = CGFloat(index) * stepX
                                let y = height - (CGFloat(value / maxValue) * height)
                                path.addLine(to: CGPoint(x: x, y: y))
                            }

                            if data.count > 0 {
                                path.addLine(to: CGPoint(x: CGFloat(data.count - 1) * stepX, y: height))
                            }
                            path.closeSubpath()
                        }
                        .fill(
                            LinearGradient(
                                colors: [Color(hex: "3B82F6").opacity(0.3), Color(hex: "3B82F6").opacity(0.05)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )

                        // Line graph
                        Path { path in
                            for (index, value) in data.enumerated() {
                                let x = CGFloat(index) * stepX
                                let y = height - (CGFloat(value / maxValue) * height)

                                if index == 0 {
                                    path.move(to: CGPoint(x: x, y: y))
                                } else {
                                    path.addLine(to: CGPoint(x: x, y: y))
                                }
                            }
                        }
                        .stroke(
                            LinearGradient(
                                colors: [Color(hex: "3B82F6"), Color(hex: "8B5CF6")],
                                startPoint: .leading,
                                endPoint: .trailing
                            ),
                            style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round)
                        )
                    }
                    .padding(.leading, 40)
                }
            }

            // X-axis time labels
            HStack {
                Text("0m")
                    .font(.system(size: 9))
                    .foregroundColor(Color(hex: "6B7280"))
                Spacer()
                if tripDuration > 120 {
                    Text(formatTime(tripDuration / 2))
                        .font(.system(size: 9))
                        .foregroundColor(Color(hex: "6B7280"))
                    Spacer()
                }
                Text(formatTime(tripDuration))
                    .font(.system(size: 9))
                    .foregroundColor(Color(hex: "6B7280"))
            }
            .padding(.leading, 40)
        }
    }
}

// MARK: - Preview

#Preview {
    TripReportView(
        isPresented: .constant(true),
        tripDuration: 1847,
        tripDistance: "15.2 km",
        alertCount: 2,
        phonePickupCount: 1,
        yawnCount: 3,
        baselineBlinkRate: 18,
        averageBlinkRate: 24,
        perclosHistory: [2, 3, 2, 5, 4, 6, 8, 7, 5, 4, 6, 8, 10, 9, 7, 8, 6, 5],
        routeCoordinates: []
    )
}
