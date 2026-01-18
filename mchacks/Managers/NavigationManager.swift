//
//  NavigationManager.swift
//  mchacks
//

import Foundation
import CoreLocation
import Combine
import MapboxDirections
import MapboxNavigationCore
import Turf

// MARK: - Maneuver Type Enum
enum ManeuverType: String {
    case straightAhead = "straight"
    case turnLeft = "turn_left"
    case turnRight = "turn_right"
    case slightLeft = "slight_left"
    case slightRight = "slight_right"
    case sharpLeft = "sharp_left"
    case sharpRight = "sharp_right"
    case uTurn = "uturn"
    case merge = "merge"
    case onRamp = "on_ramp"
    case offRamp = "off_ramp"
    case fork = "fork"
    case roundabout = "roundabout"
    case arrive = "arrive"
    case depart = "depart"

    var iconName: String {
        switch self {
        case .straightAhead: return "arrow.up"
        case .turnLeft: return "arrow.turn.up.left"
        case .turnRight: return "arrow.turn.up.right"
        case .slightLeft: return "arrow.up.left"
        case .slightRight: return "arrow.up.right"
        case .sharpLeft: return "arrow.turn.left.2"
        case .sharpRight: return "arrow.turn.right.2"
        case .uTurn: return "arrow.uturn.down"
        case .merge: return "arrow.merge"
        case .onRamp: return "arrow.up.right"
        case .offRamp: return "arrow.down.right"
        case .fork: return "arrow.branch"
        case .roundabout: return "arrow.triangle.2.circlepath"
        case .arrive: return "mappin.circle.fill"
        case .depart: return "location.fill"
        }
    }
}

@MainActor
class NavigationManager: ObservableObject {
    @Published var routeCoordinates: [CLLocationCoordinate2D]?
    @Published var isNavigating = false
    @Published var currentInstruction: String = ""
    @Published var distanceRemaining: CLLocationDistance = 0
    @Published var timeRemaining: TimeInterval = 0
    @Published var currentStepInstruction: String = ""
    @Published var distanceToNextManeuver: CLLocationDistance = 0
    @Published var isCalculatingRoute = false
    @Published var errorMessage: String?
    @Published var isRerouting = false
    @Published var currentManeuverType: ManeuverType = .straightAhead
    @Published var currentSpeedLimit: Measurement<UnitSpeed>? = nil
    @Published var hasArrivedAtDestination = false

    // Route data
    private var currentRoute: Route?
    private var routeSteps: [RouteStep] = []
    private var currentStepIndex: Int = 0
    private var originCoordinate: CLLocationCoordinate2D?
    private var destinationCoordinate: CLLocationCoordinate2D?
    private let directions: Directions

    // Speed limit data
    private var segmentSpeedLimits: [Measurement<UnitSpeed>?] = []
    private var segmentDistances: [CLLocationDistance] = []

    // Off-route detection
    private let offRouteThreshold: CLLocationDistance = 50 // meters
    private var lastRerouteTime: Date?
    private let rerouteCooldown: TimeInterval = 10 // seconds between reroutes

    init() {
        let credentials = Credentials(accessToken: "sk.eyJ1Ijoib21hcmxhaG1pbWkiLCJhIjoiY21rY3V6ZGJrMDVsZDNmcTh1bmlmZHh4cSJ9.HDp0rzKa9umGwh7YuMYpQg")
        self.directions = Directions(credentials: credentials)
    }

    func calculateRoute(from origin: CLLocationCoordinate2D, to destination: CLLocationCoordinate2D) {
        isCalculatingRoute = true
        errorMessage = nil
        originCoordinate = origin
        destinationCoordinate = destination

        let originWaypoint = Waypoint(coordinate: origin)
        let destinationWaypoint = Waypoint(coordinate: destination)

        let options = RouteOptions(waypoints: [originWaypoint, destinationWaypoint])
        options.profileIdentifier = .automobileAvoidingTraffic
        options.includesAlternativeRoutes = false
        options.routeShapeResolution = .full
        options.includesSteps = true
        options.attributeOptions = [.maximumSpeedLimit, .distance]

        _ = directions.calculate(options) { [weak self] (result: Result<RouteResponse, DirectionsError>) in
            Task { @MainActor in
                guard let self = self else { return }

                switch result {
                case .success(let response):
                    if let route = response.routes?.first,
                       let shape = route.shape {
                        self.currentRoute = route
                        self.routeCoordinates = shape.coordinates
                        self.distanceRemaining = route.distance
                        self.timeRemaining = route.expectedTravelTime

                        // Store all steps
                        self.routeSteps = route.legs.flatMap { $0.steps }
                        self.currentStepIndex = 0

                        // Get first instruction
                        if let firstStep = self.routeSteps.first {
                            self.currentStepInstruction = firstStep.instructions
                            self.distanceToNextManeuver = firstStep.distance
                        }

                        // Extract speed limit data from legs
                        self.segmentSpeedLimits = []
                        self.segmentDistances = []
                        for leg in route.legs {
                            if let speedLimits = leg.segmentMaximumSpeedLimits {
                                self.segmentSpeedLimits.append(contentsOf: speedLimits)
                            }
                            if let distances = leg.segmentDistances {
                                self.segmentDistances.append(contentsOf: distances)
                            }
                        }
                        // Set initial speed limit
                        if !self.segmentSpeedLimits.isEmpty {
                            self.currentSpeedLimit = self.segmentSpeedLimits.first ?? nil
                        }
                    }
                    self.isCalculatingRoute = false
                    self.isRerouting = false

                case .failure(let error):
                    self.errorMessage = "Failed to calculate route: \(error.localizedDescription)"
                    self.isCalculatingRoute = false
                    self.isRerouting = false
                }
            }
        }
    }

    func startNavigation() {
        guard routeCoordinates != nil else { return }
        isNavigating = true
        currentStepIndex = 0
    }

    func stopNavigation() {
        isNavigating = false
        routeCoordinates = nil
        currentRoute = nil
        routeSteps = []
        currentStepIndex = 0
        currentInstruction = ""
        distanceRemaining = 0
        timeRemaining = 0
        currentStepInstruction = ""
        distanceToNextManeuver = 0
        destinationCoordinate = nil
        originCoordinate = nil
        currentSpeedLimit = nil
        segmentSpeedLimits = []
        segmentDistances = []
        hasArrivedAtDestination = false
    }

    func updateProgress(location: CLLocation) {
        guard isNavigating,
              let routeCoords = routeCoordinates,
              routeCoords.count >= 2 else { return }

        let userCoord = location.coordinate

        // Find closest point on route
        let routeLine = LineString(routeCoords)
        let userPoint = Point(userCoord)

        // Calculate distance from user to route
        let distanceToRoute = distanceFromPointToLine(point: userCoord, line: routeCoords)

        // Check if off-route and need to reroute
        if distanceToRoute > offRouteThreshold {
            handleOffRoute(from: userCoord)
            return
        }

        // Find the closest point index on route
        let (closestIndex, _) = findClosestPointOnRoute(userCoord: userCoord, routeCoords: routeCoords)

        // Calculate remaining distance along route
        distanceRemaining = calculateRemainingDistance(from: closestIndex, along: routeCoords, userCoord: userCoord)

        // Estimate time based on current speed or average
        let speed = location.speed > 0 ? location.speed : 13.4 // ~30 mph default
        timeRemaining = distanceRemaining / speed

        // Update current step instruction
        updateCurrentStep(userCoord: userCoord, closestRouteIndex: closestIndex)

        // Update speed limit based on position
        updateSpeedLimit(routeIndex: closestIndex)

        // Check for arrival at destination using Mapbox RouteStep.maneuverType
        checkForArrival(userCoord: userCoord)
    }

    /// Detects arrival at destination using MapboxDirections RouteStep.maneuverType == .arrive
    /// This follows Mapbox Navigation SDK's arrival detection pattern
    private func checkForArrival(userCoord: CLLocationCoordinate2D) {
        guard !routeSteps.isEmpty, !hasArrivedAtDestination else { return }

        // Find the arrival step (last step with maneuverType == .arrive)
        guard let arrivalStep = routeSteps.last,
              arrivalStep.maneuverType == .arrive else { return }

        // Get the maneuverLocation from the arrival step - this is the arrival point
        let arrivalLocation = arrivalStep.maneuverLocation

        // Calculate distance to the arrival maneuver location
        let distanceToArrival = distance(from: userCoord, to: arrivalLocation)

        // Check if we're on the final step (currentStepIndex points to arrival step)
        let isOnFinalStep = currentStepIndex >= routeSteps.count - 1

        // Mapbox Navigation SDK uses ~50 meters as default arrival threshold
        // Reference: ArrivalController in MapboxNavigationCore
        let arrivalDistanceThreshold: CLLocationDistance = 50

        if isOnFinalStep && distanceToArrival <= arrivalDistanceThreshold {
            hasArrivedAtDestination = true
        }
    }

    private func updateSpeedLimit(routeIndex: Int) {
        guard !segmentSpeedLimits.isEmpty,
              !segmentDistances.isEmpty,
              segmentSpeedLimits.count == segmentDistances.count else {
            return
        }

        // Find which segment the user is on based on route index
        // Segments correspond to route coordinates
        let segmentIndex = min(routeIndex, segmentSpeedLimits.count - 1)
        currentSpeedLimit = segmentSpeedLimits[segmentIndex]
    }

    private func updateCurrentStep(userCoord: CLLocationCoordinate2D, closestRouteIndex: Int) {
        guard !routeSteps.isEmpty else { return }

        // Find which step we're on based on distance traveled
        var accumulatedDistance: CLLocationDistance = 0
        var newStepIndex = 0

        for (index, step) in routeSteps.enumerated() {
            if let stepCoords = step.shape?.coordinates, !stepCoords.isEmpty {
                // Check if user is near this step's maneuver location
                let stepStartCoord = stepCoords.first!
                let distanceToStepStart = distance(from: userCoord, to: stepStartCoord)

                // If we're within 30 meters of a step's start, we're on that step
                if distanceToStepStart < 30 {
                    newStepIndex = index
                    break
                }

                // Check if user is along this step
                let distanceToStep = distanceFromPointToLine(point: userCoord, line: stepCoords)
                if distanceToStep < 20 {
                    newStepIndex = index
                }
            }

            accumulatedDistance += step.distance
        }

        // Update step if changed
        if newStepIndex != currentStepIndex || currentStepInstruction.isEmpty {
            currentStepIndex = newStepIndex

            if currentStepIndex < routeSteps.count {
                let currentStep = routeSteps[currentStepIndex]
                currentStepInstruction = currentStep.instructions

                // Update maneuver type
                currentManeuverType = parseManeuverType(from: currentStep)

                // Calculate distance to next maneuver
                if let stepCoords = currentStep.shape?.coordinates,
                   let lastCoord = stepCoords.last {
                    distanceToNextManeuver = distance(from: userCoord, to: lastCoord)
                } else {
                    distanceToNextManeuver = currentStep.distance
                }
            }
        } else if currentStepIndex < routeSteps.count {
            // Update distance to next maneuver
            let currentStep = routeSteps[currentStepIndex]
            if let stepCoords = currentStep.shape?.coordinates,
               let lastCoord = stepCoords.last {
                distanceToNextManeuver = distance(from: userCoord, to: lastCoord)
            }
        }
    }

    private func parseManeuverType(from step: RouteStep) -> ManeuverType {
        // Check maneuver type and direction from the step
        let maneuverType = step.maneuverType
        let maneuverDirection = step.maneuverDirection

        switch maneuverType {
        case .turn:
            switch maneuverDirection {
            case .left: return .turnLeft
            case .right: return .turnRight
            case .slightLeft: return .slightLeft
            case .slightRight: return .slightRight
            case .sharpLeft: return .sharpLeft
            case .sharpRight: return .sharpRight
            case .uTurn: return .uTurn
            default: return .straightAhead
            }
        case .merge:
            return .merge
        case .takeOnRamp, .takeOffRamp:
            if maneuverDirection == .left || maneuverDirection == .slightLeft {
                return .slightLeft
            } else {
                return .slightRight
            }
        case .reachFork:
            if maneuverDirection == .left || maneuverDirection == .slightLeft {
                return .slightLeft
            } else {
                return .slightRight
            }
        case .takeRoundabout, .takeRotary:
            return .roundabout
        case .arrive:
            return .arrive
        case .depart:
            return .depart
        case .continue:
            switch maneuverDirection {
            case .left: return .slightLeft
            case .right: return .slightRight
            case .slightLeft: return .slightLeft
            case .slightRight: return .slightRight
            default: return .straightAhead
            }
        default:
            // Check direction for any other cases
            switch maneuverDirection {
            case .left: return .turnLeft
            case .right: return .turnRight
            case .slightLeft: return .slightLeft
            case .slightRight: return .slightRight
            case .sharpLeft: return .sharpLeft
            case .sharpRight: return .sharpRight
            case .uTurn: return .uTurn
            default: return .straightAhead
            }
        }
    }

    private func handleOffRoute(from coordinate: CLLocationCoordinate2D) {
        // Prevent too frequent rerouting
        if let lastReroute = lastRerouteTime,
           Date().timeIntervalSince(lastReroute) < rerouteCooldown {
            return
        }

        guard let destination = destinationCoordinate else { return }

        lastRerouteTime = Date()
        isRerouting = true

        // Recalculate route from current position
        calculateRoute(from: coordinate, to: destination)
    }

    private func findClosestPointOnRoute(userCoord: CLLocationCoordinate2D, routeCoords: [CLLocationCoordinate2D]) -> (index: Int, distance: CLLocationDistance) {
        var closestIndex = 0
        var closestDistance: CLLocationDistance = .greatestFiniteMagnitude

        for (index, coord) in routeCoords.enumerated() {
            let dist = distance(from: userCoord, to: coord)
            if dist < closestDistance {
                closestDistance = dist
                closestIndex = index
            }
        }

        return (closestIndex, closestDistance)
    }

    private func calculateRemainingDistance(from index: Int, along coords: [CLLocationCoordinate2D], userCoord: CLLocationCoordinate2D) -> CLLocationDistance {
        guard index < coords.count else { return 0 }

        var totalDistance: CLLocationDistance = 0

        // Distance from user to closest point
        totalDistance += distance(from: userCoord, to: coords[index])

        // Sum distance along remaining route
        for i in index..<(coords.count - 1) {
            totalDistance += distance(from: coords[i], to: coords[i + 1])
        }

        return totalDistance
    }

    private func distance(from: CLLocationCoordinate2D, to: CLLocationCoordinate2D) -> CLLocationDistance {
        let fromLocation = CLLocation(latitude: from.latitude, longitude: from.longitude)
        let toLocation = CLLocation(latitude: to.latitude, longitude: to.longitude)
        return fromLocation.distance(from: toLocation)
    }

    private func distanceFromPointToLine(point: CLLocationCoordinate2D, line: [CLLocationCoordinate2D]) -> CLLocationDistance {
        guard line.count >= 2 else { return .greatestFiniteMagnitude }

        var minDistance: CLLocationDistance = .greatestFiniteMagnitude

        for i in 0..<(line.count - 1) {
            let segmentStart = line[i]
            let segmentEnd = line[i + 1]
            let dist = distanceFromPointToSegment(point: point, segmentStart: segmentStart, segmentEnd: segmentEnd)
            minDistance = min(minDistance, dist)
        }

        return minDistance
    }

    private func distanceFromPointToSegment(point: CLLocationCoordinate2D, segmentStart: CLLocationCoordinate2D, segmentEnd: CLLocationCoordinate2D) -> CLLocationDistance {
        let p = point
        let a = segmentStart
        let b = segmentEnd

        let dx = b.longitude - a.longitude
        let dy = b.latitude - a.latitude

        if dx == 0 && dy == 0 {
            return distance(from: p, to: a)
        }

        let t = max(0, min(1, ((p.longitude - a.longitude) * dx + (p.latitude - a.latitude) * dy) / (dx * dx + dy * dy)))

        let projection = CLLocationCoordinate2D(
            latitude: a.latitude + t * dy,
            longitude: a.longitude + t * dx
        )

        return distance(from: p, to: projection)
    }
}

// MARK: - Formatting Helpers (Metric)
extension NavigationManager {
    var formattedDistance: String {
        if distanceRemaining >= 1000 {
            let km = distanceRemaining / 1000
            return String(format: "%.1f km", km)
        } else {
            return String(format: "%.0f m", distanceRemaining)
        }
    }

    var formattedTime: String {
        let hours = Int(timeRemaining) / 3600
        let minutes = (Int(timeRemaining) % 3600) / 60

        if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else {
            return "\(max(1, minutes)) min"
        }
    }

    var formattedETA: String {
        let eta = Date().addingTimeInterval(timeRemaining)
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: eta)
    }

    var formattedDistanceToManeuver: String {
        if distanceToNextManeuver >= 1000 {
            let km = distanceToNextManeuver / 1000
            return String(format: "%.1f km", km)
        } else {
            // Round to nearest 10m for cleaner display
            let rounded = (distanceToNextManeuver / 10).rounded() * 10
            return String(format: "%.0f m", max(10, rounded))
        }
    }

    var formattedSpeedLimit: String? {
        guard let limit = currentSpeedLimit else { return nil }
        // Convert to km/h for display
        let kmh = limit.converted(to: .kilometersPerHour).value
        return String(format: "%.0f", kmh)
    }

    var speedLimitValue: Double? {
        guard let limit = currentSpeedLimit else { return nil }
        return limit.converted(to: .kilometersPerHour).value
    }
}
