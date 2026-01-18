//
//  NavigationView.swift
//  mchacks
//
//  Redesigned navigation components
//

import SwiftUI
import CoreLocation
import AVFoundation

// MARK: - Trip Data (captures metrics at trip end)
struct TripData {
    let duration: TimeInterval
    let distance: String
    let alertCount: Int
    let phonePickupCount: Int
    let yawnCount: Int
    let baselineBlinkRate: Float
    let averageBlinkRate: Float
    let perclosHistory: [Float]  // PERCLOS values over time for graph
    let routeCoordinates: [CLLocationCoordinate2D]  // For map display
    let eventCoordinates: [CLLocationCoordinate2D]  // Locations where events occurred
}

struct MainNavigationView: View {
    @StateObject private var locationManager = LocationManager()
    @StateObject private var navigationManager = NavigationManager()
    @StateObject private var permissionManager = PermissionManager()
    @StateObject private var vapiManager = VAPIManager()

    @State private var showSearch = false
    @State private var destinationCoordinate: CLLocationCoordinate2D?
    @State private var destinationName = ""
    @State private var shouldRecenter = false
    @State private var showCompanionMode = false
    @State private var showCalibration = false
    @State private var showEmergencyContactSetup = false
    @State private var showTripReport = false
    @StateObject private var eyeState = EyeTrackingState()

    // Trip tracking for report
    @State private var tripStartTime: Date?
    @State private var tripAlertCount: Int = 0
    @State private var capturedTripData: TripData?

    // MARK: - Rest Stop & Emergency
    @State private var showQuickRestStop = false
    @State private var restStopReason = ""
    @State private var restStopAudioPlayer: AVAudioPlayer?
    @State private var lastFatigueAlertLevel: FatigueLevel = .normal

    var body: some View {
        ZStack {
            // Map
            MapboxMapView(
                userLocation: $locationManager.currentLocation,
                routeCoordinates: $navigationManager.routeCoordinates,
                destinationCoordinate: $destinationCoordinate,
                isNavigating: navigationManager.isNavigating,
                onMapTap: { coordinate in
                    if !navigationManager.isNavigating {
                        setDestination(coordinate: coordinate, name: "Dropped Pin")
                    }
                },
                shouldRecenter: shouldRecenter,
                onRecenterComplete: { shouldRecenter = false }
            )
            .ignoresSafeArea()

            // Route preview top bar
            if !navigationManager.isNavigating && navigationManager.routeCoordinates != nil {
                VStack {
                    RoutePreviewTopBar(
                        destinationName: destinationName,
                        onBack: { clearDestination() }
                    )
                    Spacer()
                }
            }

            // Navigation overlays when navigating
            if navigationManager.isNavigating {
                // Top section - Navigation instruction and camera
                VStack {
                    HStack(alignment: .top, spacing: 10) {
                        // Left - Navigation instructions (fills available space)
                        NavigationCard(
                            instruction: navigationManager.currentStepInstruction,
                            distance: navigationManager.formattedDistanceToManeuver,
                            maneuverType: navigationManager.currentManeuverType
                        )

                        // Right - Face camera (bigger square)
                        FaceCameraCard(eyeState: eyeState)
                    }
                    .padding(.top, 8)
                    .padding(.horizontal, 12)

                    Spacer()
                }

                // Bottom - Speed display and companion button
                VStack {
                    Spacer()
                    HStack(alignment: .bottom) {
                        SpeedDisplayView(
                            currentSpeed: locationManager.speed,
                            speedLimit: navigationManager.speedLimitValue
                        )
                        .padding(.leading, 16)

                        Spacer()

                        // Companion mode button - starts call directly
                        Button(action: {
                            if vapiManager.isCallActive {
                                vapiManager.endCall()
                            } else if !vapiManager.isConnecting {
                                Task { await vapiManager.startCall() }
                            }
                        }) {
                            ZStack {
                                Circle()
                                    .fill(vapiManager.isCallActive ? AppColors.error : AppColors.backgroundCard)
                                    .frame(width: 56, height: 56)

                                if vapiManager.isConnecting {
                                    // Loading spinner
                                    ProgressView()
                                        .progressViewStyle(CircularProgressViewStyle(tint: AppColors.accent))
                                        .scaleEffect(1.2)
                                } else if vapiManager.isCallActive {
                                    // Hang up icon
                                    Image(systemName: "phone.down.fill")
                                        .font(.system(size: 24, weight: .semibold))
                                        .foregroundColor(.white)
                                } else {
                                    // Call icon
                                    Image("call")
                                        .resizable()
                                        .scaledToFit()
                                        .frame(width: 28, height: 28)
                                        .foregroundColor(AppColors.accent)
                                }
                            }
                            .shadow(color: Color.black.opacity(0.3), radius: 6, y: 3)
                        }
                        .disabled(vapiManager.isConnecting)
                        .padding(.trailing, 16)
                    }
                    .padding(.bottom, 160)
                }
            }

            // UI Overlays
            VStack(spacing: 0) {
                Spacer()

                // Bottom section
                if navigationManager.isNavigating {
                    NavigationBottomBar(
                        time: navigationManager.formattedTime,
                        distance: navigationManager.formattedDistance,
                        eta: navigationManager.formattedETA,
                        destinationName: destinationName,
                        currentBlinkRate: eyeState.currentBlinkRate,
                        baselineBlinkRate: eyeState.baselineBlinkRate,
                        onEndTrip: { endTrip() },
                        onRecenter: { shouldRecenter = true },
                        onCompanion: { showCompanionMode = true },
                        onRecalibrate: {
                            NotificationCenter.default.post(name: NSNotification.Name("CalibrateNose"), object: nil)
                        }
                    )
                } else if navigationManager.routeCoordinates != nil {
                    // Route preview with top bar
                    VStack(spacing: 0) {
                        Spacer()
                        RoutePreview(
                            destinationName: destinationName,
                            time: navigationManager.formattedTime,
                            distance: navigationManager.formattedDistance,
                            onStart: { showCalibration = true },
                            onCancel: { clearDestination() }
                        )
                    }
                } else {
                    // Waze-style bottom panel
                    WazeBottomPanel(
                        onSearchTap: { showSearch = true },
                        onRecenter: { shouldRecenter = true }
                    )
                }
            }

            // Loading overlay
            if navigationManager.isCalculatingRoute {
                LoadingOverlay()
            }
        }
        .fullScreenCover(isPresented: $showSearch) {
            SearchView(
                isPresented: $showSearch,
                selectedCoordinate: $destinationCoordinate,
                selectedPlaceName: $destinationName
            )
        }
        .sheet(isPresented: $showCompanionMode) {
            CompanionModeView(
                isPresented: $showCompanionMode,
                permissionManager: permissionManager,
                vapiManager: vapiManager
            )
        }
        .sheet(isPresented: $showCalibration) {
            CalibrationView(
                isPresented: $showCalibration,
                eyeState: eyeState,
                onCalibrated: {
                    tripStartTime = Date()
                    tripAlertCount = 0
                    navigationManager.startNavigation()
                }
            )
        }
        .sheet(isPresented: $showEmergencyContactSetup) {
            EmergencyContactSetupView()
        }
        .fullScreenCover(isPresented: $showTripReport) {
            if let data = capturedTripData {
                TripReportView(
                    isPresented: $showTripReport,
                    tripDuration: data.duration,
                    tripDistance: data.distance,
                    alertCount: data.alertCount,
                    phonePickupCount: data.phonePickupCount,
                    yawnCount: data.yawnCount,
                    baselineBlinkRate: data.baselineBlinkRate,
                    averageBlinkRate: data.averageBlinkRate,
                    perclosHistory: data.perclosHistory,
                    routeCoordinates: data.routeCoordinates,
                    eventCoordinates: data.eventCoordinates
                )
            } else {
                // Fallback (shouldn't happen)
                TripReportView(
                    isPresented: $showTripReport,
                    tripDuration: 0,
                    tripDistance: "0 km",
                    alertCount: 0,
                    phonePickupCount: 0,
                    yawnCount: 0,
                    baselineBlinkRate: 0,
                    averageBlinkRate: 0,
                    perclosHistory: [],
                    routeCoordinates: [],
                    eventCoordinates: []
                )
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("ShowEmergencyContactSetup"))) { _ in
            showEmergencyContactSetup = true
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("TriggerEmergencyCall"))) { _ in
            // Emergency calls are also tracked as alerts
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("DrowsinessAlertPlayed"))) { _ in
            tripAlertCount += 1
            // Record event location for trip report map
            if let coordinate = locationManager.currentLocation?.coordinate {
                eyeState.recordEvent(at: coordinate)
            }
        }
        // MARK: - Hybrid Fatigue Level Monitoring
        // Monitor FatigueTracker's level for rest stop suggestions and emergency calls
        .onReceive(eyeState.fatigueTracker.metrics.$fatigueLevel) { newLevel in
            // Only act when navigating and level escalates
            if navigationManager.isNavigating &&
               newLevel.shouldAlert &&
               lastFatigueAlertLevel.alertPriority < newLevel.alertPriority {

                // Record event location for trip report map
                if let coordinate = locationManager.currentLocation?.coordinate {
                    eyeState.recordEvent(at: coordinate)
                }

                if newLevel == .critical {
                    // CRITICAL: Trigger emergency call (most severe intervention)
                    print("🚨 [Fatigue] CRITICAL level reached - triggering emergency call")
                    NotificationCenter.default.post(name: NSNotification.Name("TriggerEmergencyCall"), object: nil)
                } else if newLevel == .moderate || newLevel == .high {
                    // MODERATE/HIGH: Show rest stop suggestion
                    restStopReason = "fatigue_\(newLevel.rawValue)"
                    showQuickRestStop = true
                    playRestStopAudio()
                }

                lastFatigueAlertLevel = newLevel
            }
        }
        // Listen for 8th alert specifically (pit stop trigger - no regular audio)
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("PitStopAlertTriggered"))) { _ in
            if !showQuickRestStop {
                restStopReason = "multiple_alerts"
                showQuickRestStop = true
                playRestStopAudio()
                print("🛑 [RestStop] Showing suggestion after 8 alerts")
            }
        }
        .sheet(isPresented: $showQuickRestStop) {
            QuickRestStopView(
                isPresented: $showQuickRestStop,
                userLocation: locationManager.currentLocation,
                reason: restStopReason,
                onSelectStop: { coordinate, name in
                    destinationCoordinate = coordinate
                    destinationName = name
                }
            )
            .presentationDetents([.height(300)])
            .presentationDragIndicator(.hidden)
            .presentationCornerRadius(20)
            .presentationBackground(AppColors.backgroundSecondary)
        }
        .onChange(of: destinationCoordinate) { _, newValue in
            if let destination = newValue,
               let origin = locationManager.currentLocation?.coordinate {
                navigationManager.calculateRoute(from: origin, to: destination)
            }
        }
        .onChange(of: locationManager.currentLocation) { _, newValue in
            if let location = newValue {
                navigationManager.updateProgress(location: location)
            }
        }
        // Auto-end trip when user arrives at destination (Mapbox arrival detection)
        .onChange(of: navigationManager.hasArrivedAtDestination) { _, hasArrived in
            if hasArrived {
                endTrip()
            }
        }
        .onAppear {
            permissionManager.checkAllPermissions()
            permissionManager.requestLocationPermission(using: locationManager)
            locationManager.requestPermission()

            // Set up VAPIManager with AR pause/resume callbacks
            vapiManager.setupVapi()
            vapiManager.onCallWillStart = {
                NotificationCenter.default.post(name: NSNotification.Name("PauseARSession"), object: nil)
            }
            vapiManager.onCallDidEnd = {
                NotificationCenter.default.post(name: NSNotification.Name("ResumeARSession"), object: nil)
            }
        }
        .alert("Error", isPresented: .init(
            get: { navigationManager.errorMessage != nil },
            set: { if !$0 { navigationManager.errorMessage = nil } }
        )) {
            Button("OK") { navigationManager.errorMessage = nil }
        } message: {
            Text(navigationManager.errorMessage ?? "")
        }
    }

    private func setDestination(coordinate: CLLocationCoordinate2D, name: String) {
        destinationCoordinate = coordinate
        destinationName = name
    }

    private func clearDestination() {
        navigationManager.stopNavigation()
        destinationCoordinate = nil
        destinationName = ""
        resetEyeState()
    }

    private func endTrip() {
        // CAPTURE all trip data BEFORE stopping navigation (route gets cleared on stop)
        capturedTripData = TripData(
            duration: tripStartTime.map { Date().timeIntervalSince($0) } ?? 0,
            distance: navigationManager.formattedDistance,
            alertCount: tripAlertCount,
            phonePickupCount: eyeState.phonePickupCount,
            yawnCount: eyeState.yawnCount,
            baselineBlinkRate: eyeState.baselineBlinkRate,
            averageBlinkRate: eyeState.currentBlinkRate,
            perclosHistory: eyeState.perclosHistory,
            routeCoordinates: navigationManager.routeCoordinates ?? [],
            eventCoordinates: eyeState.eventCoordinates
        )

        print("📊 [Trip End] Captured - Alerts: \(tripAlertCount), Phone: \(eyeState.phonePickupCount), Yawns: \(eyeState.yawnCount), PERCLOS samples: \(eyeState.perclosHistory.count), Route points: \(navigationManager.routeCoordinates?.count ?? 0), Event locations: \(eyeState.eventCoordinates.count)")

        // Stop navigation AFTER capturing data
        navigationManager.stopNavigation()

        // Show trip report with captured data
        showTripReport = true

        // Reset AFTER showing report
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.resetEyeState()
        }
    }

    private func resetEyeState() {
        eyeState.isCalibrated = false
        eyeState.noseOffsetX = 0.0
        eyeState.noseOffsetY = 0.0
        eyeState.blinkCount = 0
        NotificationCenter.default.post(name: NSNotification.Name("ResetCalibration"), object: nil)
    }

    private func playRestStopAudio() {
        // Stop any currently playing rest stop audio first
        restStopAudioPlayer?.stop()

        guard let url = Bundle.main.url(forResource: "RestStopSuggestion", withExtension: "mp3") else {
            print("⚠️ [RestStop] Audio file not found: RestStopSuggestion.mp3")
            return
        }

        do {
            restStopAudioPlayer = try AVAudioPlayer(contentsOf: url)
            restStopAudioPlayer?.volume = 1.0
            restStopAudioPlayer?.play()
            print("🔊 [RestStop] Playing rest stop suggestion audio")
        } catch {
            print("⚠️ [RestStop] Failed to play audio: \(error)")
        }
    }
}

// MARK: - Waze Bottom Panel
struct WazeBottomPanel: View {
    let onSearchTap: () -> Void
    let onRecenter: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Handle indicator
            Capsule()
                .fill(Color.white.opacity(0.4))
                .frame(width: 40, height: 5)
                .padding(.top, 12)
                .padding(.bottom, 16)

            // Search bar
            Button(action: onSearchTap) {
                HStack(spacing: 14) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundColor(AppColors.textSecondary)

                    Text("Where to?")
                        .font(.system(size: 18, weight: .regular))
                        .foregroundColor(AppColors.textSecondary)

                    Spacer()

                    Image(systemName: "mic.fill")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundColor(AppColors.textSecondary)
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 18)
                .background(AppColors.backgroundCard)
                .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 20)
        }
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(AppColors.backgroundSecondary)
                .ignoresSafeArea(edges: .bottom)
        )
    }
}

// MARK: - Search Bar View (Legacy - kept for compatibility)
struct SearchBarView: View {
    let destinationName: String
    let onTap: () -> Void
    let onClear: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 14) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundColor(AppColors.textSecondary)

                Text(destinationName.isEmpty ? "Search destination" : destinationName)
                    .font(.system(size: 17))
                    .foregroundColor(destinationName.isEmpty ? AppColors.textSecondary : AppColors.textPrimary)
                    .lineLimit(1)

                Spacer()

                if !destinationName.isEmpty {
                    Button(action: onClear) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 20))
                            .foregroundColor(AppColors.textTertiary)
                    }
                } else {
                    Image(systemName: "mic.fill")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(AppColors.textSecondary)
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 16)
            .background(AppColors.backgroundCard)
            .clipShape(Capsule())
        }
        .padding(.horizontal, 16)
    }
}

// MARK: - Navigation Card (Waze Style)
struct NavigationCard: View {
    let instruction: String
    let distance: String
    let maneuverType: ManeuverType
    var nextInstruction: String? = nil
    var nextManeuverType: ManeuverType? = nil

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            // Large turn arrow
            Image(systemName: maneuverType.iconName)
                .font(.system(size: 40, weight: .bold))
                .foregroundColor(.white)
                .frame(width: 50)

            VStack(alignment: .leading, spacing: 4) {
                // Distance
                Text(distance)
                    .font(.system(size: 28, weight: .bold))
                    .foregroundColor(.white)

                // Street name in cyan
                Text(instruction.isEmpty ? "Follow the route" : instruction)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(AppColors.accent)
                    .lineLimit(2)
            }

            Spacer()
        }
        .padding(.horizontal, 18)
        .frame(maxWidth: .infinity)
        .frame(height: 115)
        .background(AppColors.backgroundSecondary.opacity(0.95))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

// MARK: - Face Camera Card (Waze Style)
struct FaceCameraCard: View {
    @ObservedObject var eyeState: EyeTrackingState

    var body: some View {
        ZStack {
            ARFaceTrackingView(eyeState: eyeState)
                .frame(width: 115, height: 115)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

            // Position indicator (moves based on head position)
            if eyeState.isCalibrated {
                VStack {
                    HStack {
                        Spacer()
                        PositionIndicatorView(
                            offsetX: CGFloat(eyeState.noseOffsetX),
                            offsetY: CGFloat(eyeState.noseOffsetY)
                        )
                        .padding(6)
                    }
                    Spacer()
                }
            } else {
                // Static warning dot when not calibrated
                VStack {
                    HStack {
                        Spacer()
                        Circle()
                            .fill(AppColors.warning)
                            .frame(width: 12, height: 12)
                            .shadow(color: AppColors.warning.opacity(0.6), radius: 4)
                            .padding(8)
                    }
                    Spacer()
                }
            }
        }
        .frame(width: 115, height: 115)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(AppColors.backgroundCard, lineWidth: 3)
        )
        .shadow(color: Color.black.opacity(0.3), radius: 8, y: 4)
    }
}

// MARK: - Navigation Bottom Bar (Waze Style)
struct NavigationBottomBar: View {
    let time: String
    let distance: String
    let eta: String
    let destinationName: String
    let currentBlinkRate: Float
    let baselineBlinkRate: Float
    let onEndTrip: () -> Void
    let onRecenter: () -> Void
    let onCompanion: () -> Void
    let onRecalibrate: () -> Void

    @State private var isExpanded = false

    var body: some View {
        VStack(spacing: 0) {
            // Handle bar at top
            Capsule()
                .fill(AppColors.textMuted)
                .frame(width: 40, height: 5)
                .padding(.top, 10)
                .padding(.bottom, 14)

            // Main bar content
            HStack {
                // Search icon with gray circle
                Button(action: { withAnimation(.spring(response: 0.3)) { isExpanded.toggle() } }) {
                    ZStack {
                        Circle()
                            .fill(AppColors.backgroundCard)
                            .frame(width: 52, height: 52)

                        Image("search")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 26, height: 26)
                            .foregroundColor(AppColors.textSecondary)
                    }
                }
                .padding(.leading, 20)

                Spacer()

                // ETA and time/distance - bigger and white
                VStack(spacing: 6) {
                    Text(eta)
                        .font(.system(size: 32, weight: .bold))
                        .foregroundColor(.white)

                    Text("\(time) · \(distance)")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(.white)
                }

                Spacer()

                // Balance spacer
                Color.clear
                    .frame(width: 52, height: 52)
                    .padding(.trailing, 20)
            }
            .padding(.bottom, 8)

            if isExpanded {
                // Expanded content
                VStack(spacing: 16) {
                    // Destination
                    Text("To \(destinationName)")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(AppColors.textSecondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 20)

                    // Stop and Resume buttons - Stop smaller width, same height
                    HStack(spacing: 12) {
                        Button(action: onEndTrip) {
                            Text("Stop")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundColor(.white)
                                .frame(width: 100)
                                .padding(.vertical, 16)
                                .background(AppColors.error.opacity(0.8))
                                .clipShape(RoundedRectangle(cornerRadius: 28))
                        }

                        Button(action: onRecenter) {
                            Text("Resume")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(.black)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 16)
                                .background(AppColors.accent)
                                .clipShape(RoundedRectangle(cornerRadius: 28))
                        }
                    }
                    .padding(.horizontal, 16)
                }
                .padding(.bottom, 20)
            }
        }
        .padding(.bottom, 16)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(AppColors.backgroundSecondary)
                .ignoresSafeArea(edges: .bottom)
        )
    }
}

// MARK: - Quick Action Button (Waze Style)
struct QuickActionButton: View {
    let icon: String
    let label: String

    var body: some View {
        Button(action: {}) {
            VStack(spacing: 6) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(AppColors.backgroundCard)
                        .frame(width: 56, height: 56)

                    Image(systemName: icon)
                        .font(.system(size: 22, weight: .medium))
                        .foregroundColor(AppColors.accent)
                }
            }
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Glass Action Button
struct GlassActionButton: View {
    let icon: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(.white)
                .frame(width: 40, height: 40)
                .background(.ultraThinMaterial)
                .clipShape(Circle())
                .overlay(
                    Circle()
                        .stroke(Color.white.opacity(0.08), lineWidth: 0.5)
                )
        }
    }
}

// MARK: - Action Button (Glass Style)
struct ActionButton: View {
    let icon: String
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(.white)
                .frame(width: 42, height: 42)
                .background(.ultraThinMaterial)
                .clipShape(Circle())
                .overlay(
                    Circle()
                        .stroke(Color.white.opacity(0.08), lineWidth: 0.5)
                )
        }
    }
}

// MARK: - Route Preview Top Bar (Waze Style)
struct RoutePreviewTopBar: View {
    let destinationName: String
    let onBack: () -> Void

    var body: some View {
        HStack(spacing: 16) {
            Button(action: onBack) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundColor(AppColors.textPrimary)
            }

            Spacer()

            HStack(spacing: 8) {
                Text("Your location")
                    .font(.system(size: 15, weight: .regular))
                    .foregroundColor(AppColors.textPrimary)

                Image(systemName: "arrow.right")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(AppColors.textSecondary)

                Text(destinationName)
                    .font(.system(size: 15, weight: .regular))
                    .foregroundColor(AppColors.textPrimary)
                    .lineLimit(1)
            }

            Spacer()

            // Invisible spacer to balance the back button
            Color.clear
                .frame(width: 20, height: 20)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(AppColors.backgroundSecondary.opacity(0.95))
    }
}

// MARK: - Route Preview (Waze Style)
struct RoutePreview: View {
    let destinationName: String
    let time: String
    let distance: String
    let onStart: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Handle indicator
            Capsule()
                .fill(Color.white.opacity(0.4))
                .frame(width: 40, height: 5)
                .padding(.top, 12)
                .padding(.bottom, 20)

            // Time and distance row
            HStack(alignment: .firstTextBaseline) {
                Text(time)
                    .font(.system(size: 32, weight: .bold))
                    .foregroundColor(AppColors.textPrimary)

                Spacer()

                Text(distance)
                    .font(.system(size: 16, weight: .regular))
                    .foregroundColor(AppColors.textSecondary)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 8)

            // Route description
            VStack(alignment: .leading, spacing: 4) {
                Text("Via \(destinationName)")
                    .font(.system(size: 15, weight: .regular))
                    .foregroundColor(AppColors.textPrimary)
                    .lineLimit(1)

                Text("Best route")
                    .font(.system(size: 14, weight: .regular))
                    .foregroundColor(AppColors.textSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20)
            .padding(.bottom, 24)

            // Buttons row
            HStack(spacing: 12) {
                // Leave later button
                Button(action: onCancel) {
                    Text("Leave later")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(AppColors.textPrimary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 18)
                        .background(AppColors.backgroundCard)
                        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                }

                // Go now button
                Button(action: onStart) {
                    Text("Go now")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 18)
                        .background(AppColors.accent)
                        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 34)
        }
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(AppColors.backgroundSecondary)
                .ignoresSafeArea(edges: .bottom)
        )
    }
}

// MARK: - Recenter Button (Waze Style)
struct RecenterButton: View {
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            Image(systemName: "location.fill")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(AppColors.accent)
                .frame(width: 44, height: 44)
                .background(AppColors.backgroundElevated)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .shadow(color: Color.black.opacity(0.4), radius: 8, y: 3)
        }
    }
}

// MARK: - Loading Overlay (Waze Style)
struct LoadingOverlay: View {
    @State private var isAnimating = false

    var body: some View {
        ZStack {
            Color.black.opacity(0.5)
                .ignoresSafeArea()

            VStack(spacing: 20) {
                // Custom circular spinner
                ZStack {
                    Circle()
                        .stroke(AppColors.textMuted, lineWidth: 4)
                        .frame(width: 50, height: 50)

                    Circle()
                        .trim(from: 0, to: 0.3)
                        .stroke(AppColors.accent, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                        .frame(width: 50, height: 50)
                        .rotationEffect(Angle(degrees: isAnimating ? 360 : 0))
                        .animation(.linear(duration: 1).repeatForever(autoreverses: false), value: isAnimating)
                }

                Text("Calculating route...")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(AppColors.textPrimary)
            }
            .padding(.horizontal, 50)
            .padding(.vertical, 35)
            .background(AppColors.backgroundCard)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
        .onAppear {
            isAnimating = true
        }
    }
}

// MARK: - Companion Mode View
struct CompanionModeView: View {
    @Binding var isPresented: Bool
    @ObservedObject var permissionManager: PermissionManager
    @ObservedObject var vapiManager: VAPIManager
    @State private var showPermissionAlert = false
    @State private var isRequestingPermission = false

    var body: some View {
        NavigationStack {
            ZStack {
                AppColors.backgroundPrimary
                    .ignoresSafeArea()

                if !permissionManager.isMicrophoneAuthorized && !isRequestingPermission {
                    MicPermissionView(
                        onRequest: {
                            isRequestingPermission = true
                            Task {
                                let granted = await permissionManager.requestMicrophonePermission()
                                if !granted { showPermissionAlert = true }
                                isRequestingPermission = false
                            }
                        }
                    )
                } else if vapiManager.isCallActive {
                    ActiveCallContent(
                        vapiManager: vapiManager,
                        onEndCall: { vapiManager.endCall() }
                    )
                } else {
                    StartCallContent(
                        isConnecting: vapiManager.isConnecting,
                        onStart: { Task { await vapiManager.startCall() } },
                        onCancel: { isPresented = false }
                    )
                }
            }
            .navigationTitle(vapiManager.isCallActive ? "Companion Active" : "Stay Alert")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    if !vapiManager.isCallActive {
                        Button(action: { isPresented = false }) {
                            Image(systemName: "xmark")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(AppColors.textTertiary)
                                .frame(width: 28, height: 28)
                                .background(AppColors.backgroundElevated)
                                .clipShape(Circle())
                        }
                    }
                }
            }
            .alert("Microphone Permission Required", isPresented: $showPermissionAlert) {
                Button("Settings") { permissionManager.openSettings() }
                Button("Cancel", role: .cancel) { isPresented = false }
            } message: {
                Text("Please enable microphone access in Settings.")
            }
            .onAppear {
                permissionManager.checkAllPermissions()
            }
        }
    }
}

// MARK: - Mic Permission View
struct MicPermissionView: View {
    let onRequest: () -> Void

    var body: some View {
        VStack(spacing: 32) {
            Spacer()

            ZStack {
                Circle()
                    .fill(AppColors.accent.opacity(0.15))
                    .frame(width: 120, height: 120)

                Image(systemName: "mic.fill")
                    .font(.system(size: 48))
                    .foregroundColor(AppColors.accent)
            }

            VStack(spacing: 12) {
                Text("Microphone Access")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(AppColors.textPrimary)

                Text("Companion mode needs microphone access to chat with you.")
                    .font(.system(size: 16))
                    .foregroundColor(AppColors.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }

            Spacer()

            Button(action: onRequest) {
                Text("Enable Microphone")
                    .appButton()
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 40)
        }
    }
}

// MARK: - Start Call Content
struct StartCallContent: View {
    let isConnecting: Bool
    let onStart: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 32) {
            Spacer()

            ZStack {
                Circle()
                    .fill(AppColors.accent.opacity(0.15))
                    .frame(width: 160, height: 160)

                Image(systemName: "waveform.circle.fill")
                    .font(.system(size: 100))
                    .foregroundColor(AppColors.accent)
            }

            VStack(spacing: 12) {
                Text("Companion Mode")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundColor(AppColors.textPrimary)

                Text("Your AI co-pilot will chat with you to help you stay alert.")
                    .font(.system(size: 16))
                    .foregroundColor(AppColors.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }

            Spacer()

            VStack(spacing: 16) {
                Button(action: onStart) {
                    HStack(spacing: 12) {
                        if isConnecting {
                            ProgressView()
                                .tint(.white)
                        } else {
                            Image(systemName: "phone.fill")
                                .font(.system(size: 18))
                        }
                        Text(isConnecting ? "Connecting..." : "Start Conversation")
                            .font(.system(size: 17, weight: .semibold))
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(AppColors.accent)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                .disabled(isConnecting)

                Button("Not Now", action: onCancel)
                    .foregroundColor(AppColors.textTertiary)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 40)
        }
    }
}

// MARK: - Active Call Content
struct ActiveCallContent: View {
    @ObservedObject var vapiManager: VAPIManager
    let onEndCall: () -> Void

    @State private var pulseScale: CGFloat = 1.0

    var body: some View {
        VStack(spacing: 40) {
            Spacer()

            // Animated waveform
            ZStack {
                ForEach(0..<3, id: \.self) { index in
                    Circle()
                        .stroke(AppColors.accent.opacity(0.3), lineWidth: 2)
                        .frame(width: 140 + CGFloat(index * 40), height: 140 + CGFloat(index * 40))
                        .scaleEffect(pulseScale)
                        .animation(
                            .easeInOut(duration: 1.5)
                            .repeatForever(autoreverses: true)
                            .delay(Double(index) * 0.2),
                            value: pulseScale
                        )
                }

                Circle()
                    .fill(AppColors.accent)
                    .frame(width: 120, height: 120)

                Image(systemName: "waveform")
                    .font(.system(size: 44, weight: .medium))
                    .foregroundColor(.white)
            }
            .onAppear { pulseScale = 1.1 }

            VStack(spacing: 8) {
                Text("Companion Active")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(AppColors.textPrimary)

                Text(vapiManager.formattedDuration)
                    .font(.system(size: 48, weight: .light, design: .monospaced))
                    .foregroundColor(AppColors.textSecondary)
            }

            Spacer()

            // Controls
            HStack(spacing: 50) {
                // Mute
                Button(action: { vapiManager.toggleMute() }) {
                    VStack(spacing: 8) {
                        ZStack {
                            Circle()
                                .fill(vapiManager.isMuted ? AppColors.error : AppColors.backgroundElevated)
                                .frame(width: 56, height: 56)

                            Image(systemName: vapiManager.isMuted ? "mic.slash.fill" : "mic.fill")
                                .font(.system(size: 22))
                                .foregroundColor(.white)
                        }
                        Text(vapiManager.isMuted ? "Unmute" : "Mute")
                            .font(.system(size: 12))
                            .foregroundColor(AppColors.textTertiary)
                    }
                }

                // End call
                Button(action: onEndCall) {
                    VStack(spacing: 8) {
                        ZStack {
                            Circle()
                                .fill(AppColors.error)
                                .frame(width: 64, height: 64)

                            Image(systemName: "phone.down.fill")
                                .font(.system(size: 26))
                                .foregroundColor(.white)
                        }
                        Text("End")
                            .font(.system(size: 12))
                            .foregroundColor(AppColors.textTertiary)
                    }
                }
            }
            .padding(.bottom, 60)
        }
    }
}

// MARK: - Blink Rate Indicator (kept for compatibility)
struct BlinkRateIndicator: View {
    let currentRate: Float
    let baselineRate: Float
    let blinkCount: Int

    private var statusColor: Color {
        guard baselineRate > 0, currentRate > 0 else { return AppColors.success }
        let deviation = abs(currentRate - baselineRate) / baselineRate
        if deviation < 0.3 { return AppColors.success }
        else if deviation < 0.5 { return AppColors.warning }
        else { return AppColors.error }
    }

    var body: some View {
        Circle()
            .fill(statusColor)
            .frame(width: 16, height: 16)
            .shadow(color: statusColor.opacity(0.6), radius: 4)
    }
}

// MARK: - Navigation Instruction Banner (kept for compatibility)
struct NavigationInstructionBanner: View {
    let instruction: String
    let distanceToManeuver: String
    let isRerouting: Bool
    let onClose: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            VStack(spacing: 2) {
                Text(distanceToManeuver)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(.white)
            }
            .frame(width: 70)

            VStack(alignment: .leading, spacing: 2) {
                Text(isRerouting ? "Rerouting..." : (instruction.isEmpty ? "Follow the route" : instruction))
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.white)
                    .lineLimit(2)
            }

            Spacer()

            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.white.opacity(0.8))
                    .frame(width: 28, height: 28)
                    .background(Color.white.opacity(0.2))
                    .clipShape(Circle())
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(isRerouting ? AppColors.warning : AppColors.accent)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal, 16)
    }
}

// MARK: - Speed Display View (Waze Circle Style)
struct SpeedDisplayView: View {
    let currentSpeed: CLLocationSpeed // m/s
    let speedLimit: Double? // km/h

    private var displaySpeed: String {
        "\(max(0, Int(currentSpeed * 3.6)))"
    }

    private var speedKmh: Double {
        currentSpeed * 3.6
    }

    private var isOverSpeed: Bool {
        guard let limit = speedLimit else { return false }
        return speedKmh > limit
    }

    var body: some View {
        VStack(spacing: 8) {
            // Speed circle (Waze style - gray with black border)
            ZStack {
                Circle()
                    .fill(Color(white: 0.35))
                    .frame(width: 70, height: 70)

                Circle()
                    .stroke(isOverSpeed ? AppColors.error : Color.black, lineWidth: 5)
                    .frame(width: 70, height: 70)

                VStack(spacing: 0) {
                    Text(displaySpeed)
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundColor(isOverSpeed ? AppColors.error : .white)

                    Text("km/h")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(.white.opacity(0.7))
                }
            }
            .shadow(color: Color.black.opacity(0.4), radius: 8, y: 4)

            // Speed limit (if available and exceeding)
            if let limit = speedLimit, limit < Double.infinity {
                SpeedLimitSign(limit: Int(limit), compact: true)
            }
        }
    }
}

// MARK: - Speed Limit Sign (Clean Style)
struct SpeedLimitSign: View {
    let limit: Int
    var compact: Bool = false

    var body: some View {
        ZStack {
            // White background
            Circle()
                .fill(Color.white)
                .frame(width: compact ? 36 : 50, height: compact ? 36 : 50)

            // Red border ring
            Circle()
                .stroke(Color.red, lineWidth: compact ? 2.5 : 3.5)
                .frame(width: compact ? 32 : 46, height: compact ? 32 : 46)

            // Speed value
            Text("\(limit)")
                .font(.system(size: compact ? 13 : 18, weight: .bold, design: .rounded))
                .foregroundColor(.black)
        }
        .shadow(color: Color.black.opacity(0.15), radius: 4, y: 2)
    }
}

// MARK: - Waze Map Action Buttons
struct WazeMapActionButtons: View {
    let onReport: () -> Void
    let onAlert: () -> Void

    var body: some View {
        HStack(spacing: 16) {
            // Report button (Waze logo style)
            Button(action: onReport) {
                ZStack {
                    Circle()
                        .fill(AppColors.backgroundCard)
                        .frame(width: 56, height: 56)

                    // Waze-style icon (triangle/navigation)
                    Image(systemName: "location.north.fill")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundColor(AppColors.accent)
                        .rotationEffect(.degrees(0))
                }
                .shadow(color: Color.black.opacity(0.3), radius: 6, y: 3)
            }

            // Alert/Hazard button
            Button(action: onAlert) {
                ZStack {
                    Circle()
                        .fill(AppColors.warning)
                        .frame(width: 48, height: 48)

                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(.black)
                }
                .shadow(color: Color.black.opacity(0.3), radius: 6, y: 3)
            }
        }
    }
}

// Keep old struct names for compatibility
typealias SearchBarButton = SearchBarView
typealias ActiveNavigationBar = NavigationBottomBar
typealias RoutePreviewBar = RoutePreview
typealias DefaultBottomBar = RecenterButton
typealias NavigationSquareView = NavigationCard
typealias FaceCameraSquareView = FaceCameraCard
typealias StartCallView = StartCallContent
typealias ActiveCallView = ActiveCallContent
