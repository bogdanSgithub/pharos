//
//  MapboxMapView.swift
//  mchacks
//

import SwiftUI
import MapboxMaps
import CoreLocation
import Turf
import UIKit

struct MapboxMapView: UIViewRepresentable {
    @Binding var userLocation: CLLocation?
    @Binding var routeCoordinates: [CLLocationCoordinate2D]?
    @Binding var destinationCoordinate: CLLocationCoordinate2D?
    var isNavigating: Bool
    var onMapTap: ((CLLocationCoordinate2D) -> Void)?
    var shouldRecenter: Bool
    var onRecenterComplete: (() -> Void)?

    func makeUIView(context: Context) -> MapView {
        let cameraOptions = CameraOptions(
            zoom: 14,
            bearing: 0,
            pitch: 15
        )
        let mapInitOptions = MapInitOptions(
            cameraOptions: cameraOptions,
            styleURI: .standard
        )

        let mapView = MapView(frame: .zero, mapInitOptions: mapInitOptions)
        mapView.autoresizingMask = [.flexibleWidth, .flexibleHeight]

        // Hide scale bar
        mapView.ornaments.options.scaleBar.visibility = .hidden

        // Enable location puck - default blue dot
        mapView.location.options.puckType = .puck2D(Puck2DConfiguration.makeDefault(showBearing: true))
        mapView.location.options.puckBearing = .heading
        mapView.location.options.puckBearingEnabled = true

        // Enable gestures
        mapView.gestures.options.pitchEnabled = true
        mapView.gestures.options.rotateEnabled = true

        // Add tap gesture
        let tapGesture = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap(_:)))
        mapView.addGestureRecognizer(tapGesture)

        context.coordinator.mapView = mapView

        return mapView
    }

    func updateUIView(_ mapView: MapView, context: Context) {
        if !context.coordinator.didInitialCenter,
           let location = userLocation {

            let camera = CameraOptions(
                center: location.coordinate,
                zoom: 15,
                bearing: location.course >= 0 ? location.course : 0,
                pitch: 15
            )

            mapView.camera.ease(to: camera, duration: 0.8)
            context.coordinator.didInitialCenter = true
        }

        // Update puck style
        if isNavigating && !context.coordinator.wasNavigating {
            var config = Puck2DConfiguration()
            config.topImage = createNavigationArrow()
            config.scale = .constant(0.8)
            mapView.location.options.puckType = .puck2D(config)
            mapView.location.options.puckBearing = .course
            mapView.location.options.puckBearingEnabled = true

        } else if !isNavigating && context.coordinator.wasNavigating {
            mapView.location.options.puckType = .puck2D(
                Puck2DConfiguration.makeDefault(showBearing: true)
            )
            mapView.location.options.puckBearing = .heading
        }

        // Navigation follow mode
        if isNavigating, let location = userLocation {

            if !context.coordinator.wasNavigating {
                let camera = CameraOptions(
                    center: location.coordinate,
                    zoom: 14,
                    bearing: location.course >= 0 ? location.course : 0,
                    pitch: 45
                )
                mapView.camera.ease(to: camera, duration: 0.8)
                context.coordinator.wasNavigating = true

            } else {
                let camera = CameraOptions(
                    center: location.coordinate,
                    zoom: 14,
                    bearing: location.course >= 0 ? location.course : nil,
                    pitch: 45
                )
                mapView.camera.ease(to: camera, duration: 0.3)
            }

        } else if !isNavigating && context.coordinator.wasNavigating {
            context.coordinator.wasNavigating = false
        }

        // Manual recenter
        if shouldRecenter, let location = userLocation {
            let camera = CameraOptions(
                center: location.coordinate,
                zoom: 14,
                bearing: isNavigating && location.course >= 0 ? location.course : 0,
                pitch: isNavigating ? 45 : 15
            )

            mapView.camera.ease(to: camera, duration: 0.5)
            DispatchQueue.main.async {
                onRecenterComplete?()
            }
        }

        // Route & destination
        context.coordinator.updateRoute(
            routeCoordinates,
            userLocation: isNavigating ? userLocation : nil,
            on: mapView,
            fitToRoute: !isNavigating
        )

        context.coordinator.updateDestination(
            destinationCoordinate,
            on: mapView
        )
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onMapTap: onMapTap)
    }

    class Coordinator: NSObject {
        var mapView: MapView?
        var onMapTap: ((CLLocationCoordinate2D) -> Void)?
        var wasNavigating = false
        var didInitialCenter = false
        private var routeLayerAdded = false
        private var completedRouteLayerAdded = false
        private var startingPointLayerAdded = false
        private var lastRouteCoordinates: [CLLocationCoordinate2D]?
        private var lastDestinationCoordinate: CLLocationCoordinate2D?
        private var lastUserLocation: CLLocationCoordinate2D?

        // Mapbox PointAnnotationManager for destination marker
        private var pointAnnotationManager: PointAnnotationManager?
        private var destinationAnnotationId: String?

        init(onMapTap: ((CLLocationCoordinate2D) -> Void)?) {
            self.onMapTap = onMapTap
        }

        @objc func handleTap(_ gesture: UITapGestureRecognizer) {
            guard let mapView = mapView else { return }
            let point = gesture.location(in: mapView)
            let coordinate = mapView.mapboxMap.coordinate(for: point)
            onMapTap?(coordinate)
        }

        func updateRoute(_ coordinates: [CLLocationCoordinate2D]?, userLocation: CLLocation?, on mapView: MapView, fitToRoute: Bool = true) {
            let remainingSourceId = "route-remaining-source"
            let remainingLayerId = "route-remaining-layer"
            let completedSourceId = "route-completed-source"
            let completedLayerId = "route-completed-layer"
            let startingSourceId = "route-starting-source"
            let startingLayerId = "route-starting-layer"

            // Check if coordinates or user location changed significantly
            let coordinatesChanged: Bool
            if let coords = coordinates, let lastCoords = lastRouteCoordinates {
                coordinatesChanged = coords.count != lastCoords.count ||
                    !zip(coords, lastCoords).allSatisfy { abs($0.latitude - $1.latitude) < 0.00001 && abs($0.longitude - $1.longitude) < 0.00001 }
            } else {
                coordinatesChanged = (coordinates != nil) != (lastRouteCoordinates != nil)
            }

            let userLocationChanged: Bool
            if let userCoord = userLocation?.coordinate, let lastUserCoord = lastUserLocation {
                let distance = sqrt(pow(userCoord.latitude - lastUserCoord.latitude, 2) + pow(userCoord.longitude - lastUserCoord.longitude, 2))
                userLocationChanged = distance > 0.0001 // ~10 meters
            } else {
                userLocationChanged = (userLocation != nil) != (lastUserLocation != nil)
            }

            // Only update if something changed
            guard coordinatesChanged || userLocationChanged else { return }

            // Remove existing layers
            if routeLayerAdded {
                try? mapView.mapboxMap.removeLayer(withId: remainingLayerId)
                try? mapView.mapboxMap.removeSource(withId: remainingSourceId)
                routeLayerAdded = false
            }
            if completedRouteLayerAdded {
                try? mapView.mapboxMap.removeLayer(withId: completedLayerId)
                try? mapView.mapboxMap.removeSource(withId: completedSourceId)
                completedRouteLayerAdded = false
            }
            if startingPointLayerAdded {
                try? mapView.mapboxMap.removeLayer(withId: startingLayerId)
                try? mapView.mapboxMap.removeSource(withId: startingSourceId)
                startingPointLayerAdded = false
            }

            // Update stored values
            lastRouteCoordinates = coordinates
            lastUserLocation = userLocation?.coordinate

            guard let coordinates = coordinates, coordinates.count >= 2 else { return }

            // Add starting point marker (white circle)
            let startCoord = coordinates[0]
            var startingSource = GeoJSONSource(id: startingSourceId)
            startingSource.data = .geometry(.point(Point(startCoord)))
            try? mapView.mapboxMap.addSource(startingSource)

            var startingLayer = CircleLayer(id: startingLayerId, source: startingSourceId)
            startingLayer.circleRadius = .constant(10)
            startingLayer.circleColor = .constant(StyleColor(.white))
            startingLayer.circleStrokeWidth = .constant(2)
            startingLayer.circleStrokeColor = .constant(StyleColor(UIColor.systemGray))
            try? mapView.mapboxMap.addLayer(startingLayer)
            startingPointLayerAdded = true

            // If we have a user location and are navigating, split the route
            if let userCoord = userLocation?.coordinate {
                let (completedCoords, remainingCoords) = splitRoute(coordinates, at: userCoord)

                // Add completed route (gray)
                if completedCoords.count >= 2 {
                    var completedSource = GeoJSONSource(id: completedSourceId)
                    completedSource.data = .geometry(.lineString(LineString(completedCoords)))
                    try? mapView.mapboxMap.addSource(completedSource)

                    var completedLayer = LineLayer(id: completedLayerId, source: completedSourceId)
                    completedLayer.lineColor = .constant(StyleColor(UIColor.systemGray))
                    completedLayer.lineWidth = .constant(6)
                    completedLayer.lineCap = .constant(.round)
                    completedLayer.lineJoin = .constant(.round)

                    try? mapView.mapboxMap.addLayer(completedLayer)
                    completedRouteLayerAdded = true
                }

                // Add remaining route (blue)
                if remainingCoords.count >= 2 {
                    var remainingSource = GeoJSONSource(id: remainingSourceId)
                    remainingSource.data = .geometry(.lineString(LineString(remainingCoords)))
                    try? mapView.mapboxMap.addSource(remainingSource)

                    var remainingLayer = LineLayer(id: remainingLayerId, source: remainingSourceId)
                    remainingLayer.lineColor = .constant(StyleColor(UIColor.systemBlue))
                    remainingLayer.lineWidth = .constant(6)
                    remainingLayer.lineCap = .constant(.round)
                    remainingLayer.lineJoin = .constant(.round)

                    try? mapView.mapboxMap.addLayer(remainingLayer)
                    routeLayerAdded = true
                }
            } else {
                // No user location, draw full route in blue
                var source = GeoJSONSource(id: remainingSourceId)
                source.data = .geometry(.lineString(LineString(coordinates)))
                try? mapView.mapboxMap.addSource(source)

                var layer = LineLayer(id: remainingLayerId, source: remainingSourceId)
                layer.lineColor = .constant(StyleColor(UIColor.systemBlue))
                layer.lineWidth = .constant(6)
                layer.lineCap = .constant(.round)
                layer.lineJoin = .constant(.round)

                try? mapView.mapboxMap.addLayer(layer)
                routeLayerAdded = true
            }

            // Fit camera to route only if requested (not during navigation)
            if fitToRoute {
                let cameraOptions = mapView.mapboxMap.camera(
                    for: .lineString(LineString(coordinates)),
                    padding: UIEdgeInsets(top: 100, left: 50, bottom: 250, right: 50),
                    bearing: nil,
                    pitch: nil
                )
                mapView.camera.ease(to: cameraOptions, duration: 0.5)
            }
        }

        private func splitRoute(_ coordinates: [CLLocationCoordinate2D], at userCoord: CLLocationCoordinate2D) -> (completed: [CLLocationCoordinate2D], remaining: [CLLocationCoordinate2D]) {
            guard coordinates.count >= 2 else {
                return ([], coordinates)
            }

            // Find closest point on route
            var closestIndex = 0
            var closestDistance = Double.greatestFiniteMagnitude

            for (index, coord) in coordinates.enumerated() {
                let dist = distance(from: userCoord, to: coord)
                if dist < closestDistance {
                    closestDistance = dist
                    closestIndex = index
                }
            }

            // Split at closest point
            let completed = Array(coordinates[0...closestIndex]) + [userCoord]
            let remaining = [userCoord] + Array(coordinates[closestIndex..<coordinates.count])

            return (completed, remaining)
        }

        private func distance(from: CLLocationCoordinate2D, to: CLLocationCoordinate2D) -> Double {
            let fromLocation = CLLocation(latitude: from.latitude, longitude: from.longitude)
            let toLocation = CLLocation(latitude: to.latitude, longitude: to.longitude)
            return fromLocation.distance(from: toLocation)
        }

        func updateDestination(_ coordinate: CLLocationCoordinate2D?, on mapView: MapView) {
            // Check if destination changed
            let destinationChanged: Bool
            if let coord = coordinate, let lastCoord = lastDestinationCoordinate {
                destinationChanged = abs(coord.latitude - lastCoord.latitude) >= 0.00001 ||
                    abs(coord.longitude - lastCoord.longitude) >= 0.00001
            } else {
                destinationChanged = (coordinate != nil) != (lastDestinationCoordinate != nil)
            }

            // Only update if destination changed
            guard destinationChanged else { return }

            // Initialize PointAnnotationManager if needed (Mapbox recommended approach)
            if pointAnnotationManager == nil {
                pointAnnotationManager = mapView.annotations.makePointAnnotationManager()
            }

            // Remove existing annotation
            if let manager = pointAnnotationManager {
                manager.annotations = []
            }

            // Update stored coordinate
            lastDestinationCoordinate = coordinate

            guard let coordinate = coordinate else { return }

            // Create destination marker using Mapbox PointAnnotation
            var annotation = PointAnnotation(coordinate: coordinate)

            // Use Mapbox's default destination marker icon
            annotation.image = .init(image: createDestinationMarker(), name: "destination-marker")
            annotation.iconAnchor = .bottom
            annotation.iconSize = 1.0

            // Add annotation to manager
            pointAnnotationManager?.annotations = [annotation]
            destinationAnnotationId = annotation.id
        }

        /// Creates a racing flag destination marker (Waze style)
        private func createDestinationMarker() -> UIImage {
            let size = CGSize(width: 56, height: 68)
            let renderer = UIGraphicsImageRenderer(size: size)

            return renderer.image { context in
                let ctx = context.cgContext
                let centerX = size.width / 2
                let pinTop: CGFloat = 4
                let pinRadius: CGFloat = 22

                // Draw shadow
                ctx.setShadow(offset: CGSize(width: 0, height: 3), blur: 6, color: UIColor.black.withAlphaComponent(0.4).cgColor)

                // Pin body (teardrop shape) - white background
                let pinPath = UIBezierPath()
                pinPath.move(to: CGPoint(x: centerX, y: size.height - 4))
                pinPath.addCurve(
                    to: CGPoint(x: centerX - pinRadius, y: pinTop + pinRadius),
                    controlPoint1: CGPoint(x: centerX - 4, y: size.height - 28),
                    controlPoint2: CGPoint(x: centerX - pinRadius, y: pinTop + pinRadius + 14)
                )
                pinPath.addArc(
                    withCenter: CGPoint(x: centerX, y: pinTop + pinRadius),
                    radius: pinRadius,
                    startAngle: .pi,
                    endAngle: 0,
                    clockwise: true
                )
                pinPath.addCurve(
                    to: CGPoint(x: centerX, y: size.height - 4),
                    controlPoint1: CGPoint(x: centerX + pinRadius, y: pinTop + pinRadius + 14),
                    controlPoint2: CGPoint(x: centerX + 4, y: size.height - 28)
                )
                pinPath.close()

                // Fill with white
                UIColor.white.setFill()
                pinPath.fill()

                // Remove shadow for the rest
                ctx.setShadow(offset: .zero, blur: 0)

                // Draw checkered flag pattern inside the circle
                let circleCenter = CGPoint(x: centerX, y: pinTop + pinRadius)
                let checkRadius: CGFloat = 16
                let gridSize: CGFloat = 8

                // Clip to circle for checkered pattern
                ctx.saveGState()
                let clipPath = UIBezierPath(arcCenter: circleCenter, radius: checkRadius, startAngle: 0, endAngle: .pi * 2, clockwise: true)
                clipPath.addClip()

                // Draw checkered pattern
                let startX = circleCenter.x - checkRadius
                let startY = circleCenter.y - checkRadius
                let cols = 4
                let rows = 4

                for row in 0..<rows {
                    for col in 0..<cols {
                        let isBlack = (row + col) % 2 == 0
                        if isBlack {
                            UIColor.black.setFill()
                        } else {
                            UIColor.white.setFill()
                        }
                        let rect = CGRect(
                            x: startX + CGFloat(col) * gridSize,
                            y: startY + CGFloat(row) * gridSize,
                            width: gridSize,
                            height: gridSize
                        )
                        ctx.fill(rect)
                    }
                }

                ctx.restoreGState()

                // Draw circle border
                UIColor.darkGray.setStroke()
                let borderPath = UIBezierPath(arcCenter: circleCenter, radius: checkRadius, startAngle: 0, endAngle: .pi * 2, clockwise: true)
                borderPath.lineWidth = 1.5
                borderPath.stroke()
            }
        }

        private func calculateBounds(for coordinates: [CLLocationCoordinate2D]) -> (minLat: Double, maxLat: Double, minLon: Double, maxLon: Double)? {
            guard !coordinates.isEmpty else { return nil }
            var minLat = coordinates[0].latitude
            var maxLat = coordinates[0].latitude
            var minLon = coordinates[0].longitude
            var maxLon = coordinates[0].longitude

            for coord in coordinates {
                minLat = min(minLat, coord.latitude)
                maxLat = max(maxLat, coord.latitude)
                minLon = min(minLon, coord.longitude)
                maxLon = max(maxLon, coord.longitude)
            }

            return (minLat, maxLat, minLon, maxLon)
        }
    }

    // Create a blue navigation arrow image with rounded corners and thick white border
    private func createNavigationArrow() -> UIImage {
        let size = CGSize(width: 70, height: 80)
        let renderer = UIGraphicsImageRenderer(size: size)

        return renderer.image { context in
            let ctx = context.cgContext
            let centerX = size.width / 2

            // Arrow points
            let points: [CGPoint] = [
                CGPoint(x: centerX, y: 6),                    // Top tip
                CGPoint(x: centerX + 28, y: size.height - 8), // Bottom right
                CGPoint(x: centerX, y: size.height - 24),     // Bottom center (indent)
                CGPoint(x: centerX - 28, y: size.height - 8)  // Bottom left
            ]

            // Create path with rounded corners
            let path = createRoundedPath(points: points, cornerRadius: 6)

            // Draw shadow
            ctx.setShadow(offset: CGSize(width: 0, height: 3), blur: 6, color: UIColor.black.withAlphaComponent(0.4).cgColor)

            // Draw white border first (thick)
            ctx.setStrokeColor(UIColor.white.cgColor)
            ctx.setLineWidth(8)
            ctx.setLineJoin(.round)
            ctx.addPath(path.cgPath)
            ctx.strokePath()

            // Draw blue fill on top
            ctx.setShadow(offset: .zero, blur: 0)
            ctx.setFillColor(UIColor.systemBlue.cgColor)
            ctx.addPath(path.cgPath)
            ctx.fillPath()
        }
    }

    private func createRoundedPath(points: [CGPoint], cornerRadius: CGFloat) -> UIBezierPath {
        let path = UIBezierPath()
        guard points.count >= 3 else { return path }

        for i in 0..<points.count {
            let p1 = points[(i - 1 + points.count) % points.count]
            let p2 = points[i]
            let p3 = points[(i + 1) % points.count]

            // Calculate vectors
            let v1 = CGPoint(x: p1.x - p2.x, y: p1.y - p2.y)
            let v2 = CGPoint(x: p3.x - p2.x, y: p3.y - p2.y)

            // Normalize
            let len1 = sqrt(v1.x * v1.x + v1.y * v1.y)
            let len2 = sqrt(v2.x * v2.x + v2.y * v2.y)

            let n1 = CGPoint(x: v1.x / len1, y: v1.y / len1)
            let n2 = CGPoint(x: v2.x / len2, y: v2.y / len2)

            // Points for the arc
            let radius = min(cornerRadius, min(len1, len2) / 2)
            let start = CGPoint(x: p2.x + n1.x * radius, y: p2.y + n1.y * radius)
            let end = CGPoint(x: p2.x + n2.x * radius, y: p2.y + n2.y * radius)

            if i == 0 {
                path.move(to: start)
            } else {
                path.addLine(to: start)
            }

            path.addQuadCurve(to: end, controlPoint: p2)
        }

        path.close()
        return path
    }
}
