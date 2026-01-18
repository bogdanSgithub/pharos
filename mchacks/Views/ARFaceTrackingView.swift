//
//  ARFaceTrackingView.swift
//  mchacks
//
//  Created by Muhammad Balawal Safdar on 2026-01-15.
//

import SwiftUI
import ARKit
import SceneKit
import AVFoundation
import Combine
import AudioToolbox

class EyeTrackingState: ObservableObject {
    @Published var isCalibrated = false
    @Published var noseOffsetX: Float = 0.0 // Normalized -1 to 1
    @Published var noseOffsetY: Float = 0.0 // Normalized -1 to 1
    @Published var blinkCount: Int = 0

    // Calibration step tracking
    @Published var calibrationStep: Int = 1 // 1, 2, or 3
    @Published var calibrationProgress: Float = 0.0 // 0.0 - 1.0 for progress ring
    @Published var baselineBlinkRate: Float = 0.0 // blinks per minute
    @Published var isPositionStable: Bool = false // for step 1 detection

    // Real-time blink rate tracking
    @Published var currentBlinkRate: Float = 0.0 // current blinks per minute (rolling window)

    // MARK: - Phone Pickup Detection
    @Published var phonePickupCount: Int = 0 // Number of times user picked up phone during trip
    @Published var baselineZDistance: Float = 0.0 // Baseline distance from phone to face (meters)

    // MARK: - Hybrid Fatigue Tracking
    // FatigueTracker for comprehensive weighted fatigue detection
    let fatigueTracker = FatigueTracker()

    // Expose fatigue metrics for UI and trip report
    var fatigueLevel: FatigueLevel { fatigueTracker.metrics.fatigueLevel }
    var fatigueScore: Float { fatigueTracker.metrics.fatigueScore }
    var perclos: Float { fatigueTracker.metrics.perclos }
    var perclosHistory: [Float] { fatigueTracker.metrics.perclosHistory }
    var headNodRate: Float { fatigueTracker.metrics.headNodRate }
    var yawnRate: Float { fatigueTracker.metrics.yawnRate }
    var yawnCount: Int { fatigueTracker.metrics.yawnCount }
    var gazeDeviationPercent: Float { fatigueTracker.metrics.gazeDeviationPercent }
    var longBlinkRate: Float { fatigueTracker.metrics.longBlinkRate }
    var meanBlinkDuration: TimeInterval { fatigueTracker.metrics.meanBlinkDuration }

    func resetCalibrationState() {
        calibrationStep = 1
        calibrationProgress = 0.0
        baselineBlinkRate = 0.0
        isPositionStable = false
        isCalibrated = false
        blinkCount = 0
        noseOffsetX = 0.0
        noseOffsetY = 0.0
        currentBlinkRate = 0.0
        phonePickupCount = 0
        baselineZDistance = 0.0
        fatigueTracker.reset()
    }
}

struct ARFaceTrackingView: UIViewRepresentable {
    @ObservedObject var eyeState: EyeTrackingState
    
    func makeUIView(context: Context) -> ARSCNView {
        let sceneView = ARSCNView()
        sceneView.delegate = context.coordinator
        sceneView.automaticallyUpdatesLighting = true
        context.coordinator.sceneView = sceneView
        context.coordinator.setupObservers(sceneView: sceneView)
        
        // Add observer for calibration
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("CalibrateNose"),
            object: nil,
            queue: .main
        ) { _ in
            context.coordinator.requestCalibration()
        }
        
        // Check if face tracking is supported
        guard ARFaceTrackingConfiguration.isSupported else {
            return sceneView
        }
        
        // Only start AR session if camera permission is granted
        let cameraStatus = AVCaptureDevice.authorizationStatus(for: .video)
        guard cameraStatus == .authorized else {
            return sceneView
        }
        
        // Configure face tracking ONCE when view is created
        let configuration = ARFaceTrackingConfiguration()
        configuration.isLightEstimationEnabled = true
        configuration.maximumNumberOfTrackedFaces = ARFaceTrackingConfiguration.supportedNumberOfTrackedFaces
        
        // Run the session
        sceneView.session.run(configuration, options: [.resetTracking, .removeExistingAnchors])
        
        return sceneView
    }
    
    func updateUIView(_ uiView: ARSCNView, context: Context) {
        // Check if session should be started (permission might have been granted)
        let cameraStatus = AVCaptureDevice.authorizationStatus(for: .video)
        if cameraStatus == .authorized {
            // Check if session is not running
            if uiView.session.configuration == nil {
                guard ARFaceTrackingConfiguration.isSupported else {
                    return
                }
                
                let configuration = ARFaceTrackingConfiguration()
                configuration.isLightEstimationEnabled = true
                configuration.maximumNumberOfTrackedFaces = ARFaceTrackingConfiguration.supportedNumberOfTrackedFaces
                
                uiView.session.run(configuration, options: [.resetTracking, .removeExistingAnchors])
            }
        }
    }
    
    func makeCoordinator() -> Coordinator {
        return Coordinator(eyeState: eyeState)
    }
    
    class Coordinator: NSObject, ARSCNViewDelegate {
        private var eyesClosedStartTime: Date?
        private let eyeClosedThreshold: Float = 0.5
        private let eyeClosedDuration: TimeInterval = 3.0
        private var hasNotifiedEyesClosed = false

        private var yawnStartTime: Date?
        private let yawnThreshold: Float = 0.75
        private let yawnDuration: TimeInterval = 1.5
        private var hasNotifiedYawn = false

        // Blink counter
        private var wereEyesClosed = false
        private let blinkThreshold: Float = 0.5

        private var calibratedNosePosition: SIMD3<Float>?
        private let thresholdRadius: Float = 0.07 // 7cm threshold
        private var outsideCircleStartTime: Date?
        private let outsideCircleDuration: TimeInterval = 2.0
        private var hasNotifiedOutside = false

        var eyeState: EyeTrackingState
        weak var sceneView: ARSCNView?
        private var shouldCalibrate = false
        private var lastFaceAnchor: ARFaceAnchor?

        // Observer for reset notification
        private var resetObserver: NSObjectProtocol?
        private var pauseObserver: NSObjectProtocol?
        private var resumeObserver: NSObjectProtocol?

        // Audio players for pre-recorded alerts
        private var audioPlayers: [String: AVAudioPlayer] = [:]

        // MARK: - Strike System
        private var eyesClosedStrike: Int = 0
        private var yawningStrike: Int = 0
        private var lookingAwayStrike: Int = 0
        private let strikeDuration: TimeInterval = 3.0 // 3 seconds between strikes

        // Track when each strike was triggered for timing next strike
        private var eyesClosedLastStrikeTime: Date?
        private var yawningLastStrikeTime: Date?
        private var lookingAwayLastStrikeTime: Date?

        // Haptic feedback generator
        private let heavyImpact = UIImpactFeedbackGenerator(style: .heavy)
        private let notificationFeedback = UINotificationFeedbackGenerator()
        
        // MARK: - Alert Coordination (prevents overlap)
        private var lastAlertTime: Date?
        private let alertCooldown: TimeInterval = 2.5 // Minimum seconds between ANY alerts
        private var currentlyPlayingAlert: String?

        // MARK: - Calibration Step Tracking
        private var positionSamples: [(position: SIMD3<Float>, time: Date)] = []
        private let positionCaptureCountdown: TimeInterval = 3.0 // 3 second countdown
        private var countdownStartTime: Date?
        private var isCountingDown = false

        // Step 2: Blink rate calibration
        private var calibrationStartTime: Date?
        private var calibrationBlinkCount: Int = 0
        private let blinkCalibrationDuration: TimeInterval = 7.0 // 7 seconds for blink calibration
        private var isInCalibrationMode = false

        // Calibration step observers
        private var startCalibrationObserver: NSObjectProtocol?
        private var advanceStepObserver: NSObjectProtocol?
        private var completeCalibrationObserver: NSObjectProtocol?
        private var capturePositionObserver: NSObjectProtocol?
        private var lastFaceAnchorForCalibration: ARFaceAnchor?

        // Real-time blink rate tracking (rolling 60-second window)
        private var blinkTimestamps: [Date] = []
        private let blinkRateWindowSeconds: TimeInterval = 60.0

        // MARK: - Phone Pickup Detection (Z-Distance)
        private var calibratedZDistance: Float = 0.0 // Baseline Z distance at calibration
        private let phonePickupThresholdPercent: Float = 0.25 // 25% closer than baseline = pickup
        private var phonePickupStartTime: Date?
        private let phonePickupMinDuration: TimeInterval = 1.5 // Must be closer for 1.5 sec to trigger
        private var hasNotifiedPhonePickup = false
        private var phonePickupLastAlertTime: Date?
        private let phonePickupCooldown: TimeInterval = 30.0 // 30 sec cooldown between phone pickup alerts
        private var isPhonePickupActive: Bool = false // Suppresses other alerts when true

        init(eyeState: EyeTrackingState) {
            self.eyeState = eyeState
            super.init()
            configureAudioSession()
            preloadAudioFiles()

            // If already calibrated, trigger calibration again when face is detected
            // This handles the case where a new AR session starts (new view created)
            if eyeState.isCalibrated {
                // Will calibrate automatically when first face anchor is detected
                shouldCalibrate = true
            }

            // Observe reset notification
            resetObserver = NotificationCenter.default.addObserver(
                forName: NSNotification.Name("ResetCalibration"),
                object: nil,
                queue: .main
            ) { [weak self] _ in
                self?.resetCalibration()
            }

            // Observe start calibration notification
            startCalibrationObserver = NotificationCenter.default.addObserver(
                forName: NSNotification.Name("StartCalibration"),
                object: nil,
                queue: .main
            ) { [weak self] _ in
                self?.startCalibrationMode()
            }

            // Observe advance step notification
            advanceStepObserver = NotificationCenter.default.addObserver(
                forName: NSNotification.Name("AdvanceCalibrationStep"),
                object: nil,
                queue: .main
            ) { [weak self] _ in
                self?.advanceToNextStep()
            }

            // Observe complete calibration notification
            completeCalibrationObserver = NotificationCenter.default.addObserver(
                forName: NSNotification.Name("CompleteCalibration"),
                object: nil,
                queue: .main
            ) { [weak self] _ in
                self?.completeCalibration()
            }

            // Observe position capture notification (from CalibrationView button)
            capturePositionObserver = NotificationCenter.default.addObserver(
                forName: NSNotification.Name("StartPositionCapture"),
                object: nil,
                queue: .main
            ) { [weak self] _ in
                self?.startPositionCountdown()
            }
        }
        
        func setupObservers(sceneView: ARSCNView) {
            // Listen for AR pause/resume notifications for companion mode
            pauseObserver = NotificationCenter.default.addObserver(
                forName: NSNotification.Name("PauseARSession"),
                object: nil,
                queue: .main
            ) { [weak sceneView, weak self] _ in
                // Stop any playing audio alerts
                self?.audioPlayers.values.forEach { $0.stop() }

                // Pause AR session first
                sceneView?.session.pause()
                print("AR session paused for companion mode")

                // Deactivate audio session to release it for Vapi
                do {
                    try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
                    print("AR audio session deactivated")
                } catch {
                    print("Error deactivating AR audio session: \(error)")
                }

                // Notify that AR is fully released
                NotificationCenter.default.post(name: NSNotification.Name("ARSessionFullyPaused"), object: nil)
            }
            
            resumeObserver = NotificationCenter.default.addObserver(
                forName: NSNotification.Name("ResumeARSession"),
                object: nil,
                queue: .main
            ) { [weak sceneView, weak self] _ in
                // Reconfigure audio session for AR alerts
                self?.configureAudioSession()

                if AVCaptureDevice.authorizationStatus(for: .video) == .authorized {
                    let configuration = ARFaceTrackingConfiguration()
                    sceneView?.session.run(configuration, options: [])
                    print("AR session resumed after companion mode")
                }
            }
        }
        
        deinit {
            if let observer = resetObserver {
                NotificationCenter.default.removeObserver(observer)
            }
            if let observer = pauseObserver {
                NotificationCenter.default.removeObserver(observer)
            }
            if let observer = resumeObserver {
                NotificationCenter.default.removeObserver(observer)
            }
            if let observer = startCalibrationObserver {
                NotificationCenter.default.removeObserver(observer)
            }
            if let observer = advanceStepObserver {
                NotificationCenter.default.removeObserver(observer)
            }
            if let observer = completeCalibrationObserver {
                NotificationCenter.default.removeObserver(observer)
            }
            if let observer = capturePositionObserver {
                NotificationCenter.default.removeObserver(observer)
            }
        }
        
        private func resetCalibration() {
            calibratedNosePosition = nil
            outsideCircleStartTime = nil
            hasNotifiedOutside = false
            eyesClosedStartTime = nil
            hasNotifiedEyesClosed = false
            yawnStartTime = nil
            hasNotifiedYawn = false
            wereEyesClosed = false

            // Reset strike system
            eyesClosedStrike = 0
            yawningStrike = 0
            lookingAwayStrike = 0
            eyesClosedLastStrikeTime = nil
            yawningLastStrikeTime = nil
            lookingAwayLastStrikeTime = nil
            
            // Reset alert coordination
            lastAlertTime = nil
            currentlyPlayingAlert = nil

            // Reset calibration mode
            isInCalibrationMode = false
            positionSamples.removeAll()
            countdownStartTime = nil
            isCountingDown = false
            calibrationStartTime = nil
            calibrationBlinkCount = 0
            blinkTimestamps.removeAll()

            // Reset phone pickup detection
            calibratedZDistance = 0.0
            phonePickupStartTime = nil
            hasNotifiedPhonePickup = false
            phonePickupLastAlertTime = nil
            isPhonePickupActive = false

            // Reset state
            DispatchQueue.main.async {
                self.eyeState.resetCalibrationState()
            }
            // Stop any playing audio
            audioPlayers.values.forEach { $0.stop() }
        }

        // MARK: - Emergency Call
        private func triggerEmergencyCall() {
            // Post notification to trigger emergency call from a manager that has HealthKit access
            NotificationCenter.default.post(name: NSNotification.Name("TriggerEmergencyCall"), object: nil)
        }

        // MARK: - Calibration Mode Methods

        private func startCalibrationMode() {
            isInCalibrationMode = true
            positionSamples.removeAll()
            countdownStartTime = nil
            isCountingDown = false
            calibrationStartTime = nil
            calibrationBlinkCount = 0

            DispatchQueue.main.async {
                self.eyeState.calibrationStep = 1
                self.eyeState.calibrationProgress = 0.0
                self.eyeState.isPositionStable = false
            }
        }

        private func startPositionCountdown() {
            guard isInCalibrationMode && eyeState.calibrationStep == 1 else { return }
            isCountingDown = true
            countdownStartTime = Date()

            DispatchQueue.main.async {
                self.eyeState.isPositionStable = true // Show as ready
            }
        }

        private func advanceToNextStep() {
            let currentStep = eyeState.calibrationStep

            // When advancing from step 1 to step 2, save the calibrated nose position
            if currentStep == 1, let anchor = lastFaceAnchorForCalibration {
                saveNosePosition(from: anchor)
            }

            DispatchQueue.main.async {
                if currentStep < 3 {
                    self.eyeState.calibrationStep = currentStep + 1
                    self.eyeState.calibrationProgress = 0.0

                    if self.eyeState.calibrationStep == 2 {
                        // Start blink rate calibration
                        self.calibrationStartTime = Date()
                        self.calibrationBlinkCount = 0
                    }
                }
            }
        }

        private func updateCalibrationProgress() {
            guard isInCalibrationMode else { return }

            let step = eyeState.calibrationStep

            if step == 1 {
                // Step 1: Countdown-based position capture
                if isCountingDown, let startTime = countdownStartTime {
                    let elapsed = Date().timeIntervalSince(startTime)
                    let progress = Float(min(elapsed / positionCaptureCountdown, 1.0))

                    DispatchQueue.main.async {
                        self.eyeState.calibrationProgress = progress
                    }

                    // Auto-advance after countdown
                    if elapsed >= positionCaptureCountdown {
                        isCountingDown = false
                        advanceToNextStep()
                    }
                }
            } else if step == 2 {
                // Step 2: Blink rate calibration (7 seconds)
                if let startTime = calibrationStartTime {
                    let elapsed = Date().timeIntervalSince(startTime)
                    let progress = Float(min(elapsed / blinkCalibrationDuration, 1.0))

                    DispatchQueue.main.async {
                        self.eyeState.calibrationProgress = progress
                    }

                    // Auto-advance after calibration duration
                    if elapsed >= blinkCalibrationDuration {
                        finishBlinkCalibration()
                    }
                }
            }
        }

        private func finishBlinkCalibration() {
            guard let startTime = calibrationStartTime else { return }

            let elapsed = Date().timeIntervalSince(startTime)
            let blinkRate = Float(calibrationBlinkCount) / Float(elapsed) * 60.0

            // Complete calibration automatically
            isInCalibrationMode = false

            DispatchQueue.main.async {
                self.eyeState.baselineBlinkRate = blinkRate
                self.eyeState.calibrationStep = 3
                self.eyeState.calibrationProgress = 1.0
                self.eyeState.isCalibrated = true
            }
        }

        func completeCalibration() {
            // Nose position was already saved during step 1->2 transition
            // Just mark as calibrated and exit calibration mode
            isInCalibrationMode = false

            DispatchQueue.main.async {
                self.eyeState.isCalibrated = true
            }
        }

        private func configureAudioSession() {
            do {
                let audioSession = AVAudioSession.sharedInstance()
                // Use .playback to ensure alerts play even in silent mode
                // .duckOthers lowers other audio when our alerts play
                try audioSession.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers, .mixWithOthers])
                try audioSession.setActive(true, options: [])
                print("✅ Audio session configured for alerts")
            } catch {
                print("⚠️ Failed to configure audio session: \(error)")
            }
        }
        
        private func preloadAudioFiles() {
            // Preload all audio files for instant playback
            // Strike 1 audio files (original warnings)
            let audioFiles = [
                "eyes_closed": "EyesClosedAlert",
                "yawning": "YawningAlert",
                "looking_away": "LookingAwayAlert",
                // Strike 2 audio files (escalated warnings)
                "eyes_closed_strike2": "EyesClosedStrike2",
                "yawning_strike2": "YawningStrike2",
                "looking_away_strike2": "LookingAwayStrike2",
                // Strike 3 audio file (emergency call)
                "emergency_call": "EmergencyCall",
                // Phone pickup warning (no strike system)
                "phone_pickup": "DontLookAtPhoneAlert"
            ]

            for (key, filename) in audioFiles {
                if let url = Bundle.main.url(forResource: filename, withExtension: "mp3") {
                    do {
                        let player = try AVAudioPlayer(contentsOf: url)
                        player.prepareToPlay()
                        player.volume = 1.0
                        audioPlayers[key] = player
                    } catch {
                        print("Failed to load audio file: \(filename)")
                    }
                } else {
                    print("Audio file not found: \(filename).mp3")
                }
            }
        }
        
        private func playAlert(_ type: String, strike: Int = 1) {
            print("🔔 [Alert] Attempting to play: \(type) (Strike \(strike))")
            
            // MARK: - Alert Cooldown Check (prevents overlap)
            let now = Date()
            if let lastTime = lastAlertTime {
                let elapsed = now.timeIntervalSince(lastTime)
                if elapsed < alertCooldown {
                    print("⏳ [Alert] Cooldown active (\(String(format: "%.1f", alertCooldown - elapsed))s remaining) - skipping \(type)")
                    return
                }
            }
            
            // Don't play alerts if companion mode is active (voice call in progress)
            let audioSession = AVAudioSession.sharedInstance()
            if audioSession.category == .playAndRecord {
                print("⏸️ [Alert] Skipped - Companion mode active")
                return
            }

            // Ensure audio session is configured and active
            do {
                try audioSession.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers, .mixWithOthers])
                try audioSession.setActive(true, options: [])
            } catch {
                print("⚠️ [Alert] Audio session error: \(error)")
            }

            // Stop any currently playing alert
            audioPlayers.values.forEach { $0.stop() }

            // Play the requested alert
            if let player = audioPlayers[type] {
                player.currentTime = 0
                player.volume = 1.0
                let success = player.play()
                
                if success {
                    // Update cooldown tracking
                    lastAlertTime = now
                    currentlyPlayingAlert = type
                    print("🔊 [Alert] Playing \(type): SUCCESS (cooldown started)")

                    // Notify for trip alert count tracking
                    NotificationCenter.default.post(name: NSNotification.Name("DrowsinessAlertPlayed"), object: nil)

                    // Trigger haptic feedback (vibration)
                    triggerVibration(strike: strike)
                } else {
                    print("❌ [Alert] Playing \(type): FAILED")
                }
            } else {
                print("❌ [Alert] No audio player found for: \(type)")
            }
        }

        private func triggerVibration(strike: Int) {
            DispatchQueue.main.async { [weak self] in
                switch strike {
                case 1:
                    // Single heavy impact for Strike 1
                    self?.heavyImpact.prepare()
                    self?.heavyImpact.impactOccurred()
                case 2:
                    // Double vibration for Strike 2 (more urgent)
                    self?.heavyImpact.prepare()
                    self?.heavyImpact.impactOccurred()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                        self?.heavyImpact.impactOccurred()
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                        self?.heavyImpact.impactOccurred()
                    }
                case 3:
                    // Continuous vibration pattern for Strike 3 (emergency)
                    self?.notificationFeedback.prepare()
                    self?.notificationFeedback.notificationOccurred(.error)
                    // Also trigger system vibration for maximum attention
                    AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)
                default:
                    self?.heavyImpact.impactOccurred()
                }
            }
        }
        
        func requestCalibration() {
            shouldCalibrate = true
        }
        
        func calibrate(with faceAnchor: ARFaceAnchor) {
            saveNosePosition(from: faceAnchor)
            saveZDistance(from: faceAnchor)

            DispatchQueue.main.async {
                self.eyeState.isCalibrated = true
            }
        }

        private func saveNosePosition(from faceAnchor: ARFaceAnchor) {
            // Get nose tip in local space
            let noseVertex = faceAnchor.geometry.vertices[9]

            // Convert to world space
            let localPoint4 = SIMD4<Float>(noseVertex.x, noseVertex.y, noseVertex.z, 1.0)
            let worldPoint4 = faceAnchor.transform * localPoint4
            let worldPosition = SIMD3<Float>(worldPoint4.x, worldPoint4.y, worldPoint4.z)

            calibratedNosePosition = worldPosition
        }

        /// Save baseline Z distance from phone to face at calibration
        private func saveZDistance(from faceAnchor: ARFaceAnchor) {
            // Get face position from transform (columns.3 contains translation x, y, z, w)
            let facePosition = faceAnchor.transform.columns.3
            // Z is negative (face is in front of camera), so we use absolute value
            let zDistance = abs(facePosition.z)
            calibratedZDistance = zDistance

            DispatchQueue.main.async {
                self.eyeState.baselineZDistance = zDistance
            }
            print("📱 [Calibration] Baseline Z distance: \(zDistance * 100)cm")
        }
        
        // MARK: - ARSCNViewDelegate Methods
        
        func renderer(_ renderer: SCNSceneRenderer, nodeFor anchor: ARAnchor) -> SCNNode? {
            guard anchor is ARFaceAnchor,
                  let sceneView = renderer as? ARSCNView,
                  let device = sceneView.device else {
                return nil
            }
            
            // Create face geometry
            let faceGeometry = ARSCNFaceGeometry(device: device)
            let node = SCNNode(geometry: faceGeometry)
            
            // Style the face mesh with accent color wireframe
            node.geometry?.firstMaterial?.fillMode = .lines
            node.geometry?.firstMaterial?.diffuse.contents = UIColor(red: 0.055, green: 0.647, blue: 0.914, alpha: 1.0) // AppColors.accent
            node.geometry?.firstMaterial?.lightingModel = .constant
            
            return node
        }
        
        func renderer(_ renderer: SCNSceneRenderer, didUpdate node: SCNNode, for anchor: ARAnchor) {
            guard let faceAnchor = anchor as? ARFaceAnchor else {
                return
            }

            // Store for calibration completion
            lastFaceAnchorForCalibration = faceAnchor

            // MARK: - Phone Pickup Quick Check (must run BEFORE other alerts)
            // Check if face is too close - suppresses other alerts to avoid conflicts
            if eyeState.isCalibrated && calibratedZDistance > 0 {
                let facePosition = faceAnchor.transform.columns.3
                let currentZDistance = abs(facePosition.z)
                let distanceChange = calibratedZDistance - currentZDistance
                let percentCloser = distanceChange / calibratedZDistance
                isPhonePickupActive = percentCloser > phonePickupThresholdPercent
            }

            // Check if calibration was requested
            if shouldCalibrate {
                calibrate(with: faceAnchor)
                shouldCalibrate = false
            }

            // MARK: - Calibration Mode Processing
            if isInCalibrationMode {
                // Step 1: Just waiting for user to press Ready button
                // Step 2: Blink calibration runs automatically
                // Update calibration progress (handles countdown for step 1, blink tracking for step 2)
                updateCalibrationProgress()
            }

            // Update face geometry
            if let faceGeometry = node.geometry as? ARSCNFaceGeometry {
                faceGeometry.update(from: faceAnchor.geometry)
            }
            
            let blendShapes = faceAnchor.blendShapes
            
            // Get eye blink values (0.0 = open, 1.0 = closed)
            guard let leftEyeBlink = blendShapes[.eyeBlinkLeft] as? Float,
                  let rightEyeBlink = blendShapes[.eyeBlinkRight] as? Float,
                  let jawOpen = blendShapes[.jawOpen] as? Float else {
                return
            }
            
            // Get head pitch from face transform
            let faceTransform = faceAnchor.transform
            let headPitch = -asin(faceTransform.columns.2.y) * (180.0 / .pi) // Convert to degrees
            
            // MARK: - Hybrid System: Feed data to FatigueTracker
            // This runs alongside the Strike System for comprehensive fatigue analysis
            // Skip during phone pickup - unreliable data would falsely trigger fatigue alerts
            if !isPhonePickupActive {
                eyeState.fatigueTracker.update(
                    leftEyeBlink: leftEyeBlink,
                    rightEyeBlink: rightEyeBlink,
                    headPitch: headPitch,
                    jawOpen: jawOpen,
                    noseOffsetX: eyeState.noseOffsetX,
                    noseOffsetY: eyeState.noseOffsetY,
                    isCalibrated: eyeState.isCalibrated
                )
            }
            
            // MARK: - Eye Closure Detection with Strike System
            // Check if both eyes are closed
            let bothEyesClosed = leftEyeBlink > eyeClosedThreshold && rightEyeBlink > eyeClosedThreshold

            // Skip alerts during calibration - only run detection after calibration is complete
            let shouldRunDetection = eyeState.isCalibrated && !isInCalibrationMode

            // Skip eye closure detection if phone pickup is active or during calibration
            if bothEyesClosed && !isPhonePickupActive && shouldRunDetection {
                // Start tracking when eyes first close
                if eyesClosedStartTime == nil {
                    eyesClosedStartTime = Date()
                    hasNotifiedEyesClosed = false
                    print("👁️ [Detection] Eyes closed - starting timer")
                } else {
                    if let startTime = eyesClosedStartTime {
                        let elapsed = Date().timeIntervalSince(startTime)

                        // Strike 1: Initial warning after eyeClosedDuration (3 seconds)
                        if elapsed >= eyeClosedDuration && eyesClosedStrike == 0 {
                            print("⚠️ [Strike 1] Eyes closed for \(elapsed)s - TRIGGERING ALERT")
                            self.playAlert("eyes_closed", strike: 1)
                            eyesClosedStrike = 1
                            eyesClosedLastStrikeTime = Date()
                        }
                        // Strike 2: Escalated warning after strikeDuration more seconds
                        else if eyesClosedStrike == 1,
                                let lastStrikeTime = eyesClosedLastStrikeTime,
                                Date().timeIntervalSince(lastStrikeTime) >= strikeDuration {
                            self.playAlert("eyes_closed_strike2", strike: 2)
                            eyesClosedStrike = 2
                            eyesClosedLastStrikeTime = Date()
                        }
                        // Note: Emergency call removed from Strike 3 - now triggered by FatigueTracker critical level
                    }
                }
            } else {
                // Reset when eyes open
                eyesClosedStartTime = nil
                hasNotifiedEyesClosed = false
                eyesClosedStrike = 0
                eyesClosedLastStrikeTime = nil
            }

            // MARK: - Blink Counter
            // Detect a blink: eyes were closed and now open
            if bothEyesClosed {
                wereEyesClosed = true
            } else if wereEyesClosed {
                // Eyes just opened - count as a blink
                wereEyesClosed = false

                let now = Date()

                // Track blink timestamp for rolling rate calculation
                blinkTimestamps.append(now)

                // Remove timestamps older than the window
                blinkTimestamps.removeAll { now.timeIntervalSince($0) > blinkRateWindowSeconds }

                // Calculate current blink rate (blinks per minute)
                let windowDuration = min(now.timeIntervalSince(blinkTimestamps.first ?? now), blinkRateWindowSeconds)
                let currentRate: Float
                if windowDuration > 5 { // Need at least 5 seconds of data
                    currentRate = Float(blinkTimestamps.count) / Float(windowDuration) * 60.0
                } else {
                    currentRate = 0.0
                }

                DispatchQueue.main.async {
                    self.eyeState.blinkCount += 1
                    self.eyeState.currentBlinkRate = currentRate

                    // Debug: Log every 10 blinks
                    if self.eyeState.blinkCount % 10 == 0 {
                        print("👁️ [Tracking] Blink count: \(self.eyeState.blinkCount), Rate: \(String(format: "%.1f", currentRate))/min")
                    }
                }

                // Count blinks during calibration step 2
                if isInCalibrationMode && eyeState.calibrationStep == 2 {
                    calibrationBlinkCount += 1
                }
            }

            // MARK: - Yawning Detection with Strike System
            let isYawning = jawOpen > yawnThreshold

            // Skip yawning detection if phone pickup is active or during calibration
            if isYawning && !isPhonePickupActive && shouldRunDetection {
                // Start tracking when yawn begins
                if yawnStartTime == nil {
                    yawnStartTime = Date()
                    hasNotifiedYawn = false
                    print("🥱 [Detection] Yawn detected - starting timer")
                } else {
                    if let startTime = yawnStartTime {
                        let elapsed = Date().timeIntervalSince(startTime)

                        // Strike 1: Initial warning after yawnDuration (1.5 seconds)
                        if elapsed >= yawnDuration && yawningStrike == 0 {
                            print("⚠️ [Strike 1] Yawning for \(elapsed)s - TRIGGERING ALERT")
                            self.playAlert("yawning", strike: 1)
                            yawningStrike = 1
                            yawningLastStrikeTime = Date()
                        }
                        // Strike 2: Escalated warning after strikeDuration more seconds
                        else if yawningStrike == 1,
                                let lastStrikeTime = yawningLastStrikeTime,
                                Date().timeIntervalSince(lastStrikeTime) >= strikeDuration {
                            self.playAlert("yawning_strike2", strike: 2)
                            yawningStrike = 2
                            yawningLastStrikeTime = Date()
                        }
                        // Note: Emergency call removed from Strike 3 - now triggered by FatigueTracker critical level
                    }
                }
            } else {
                // Reset when yawning stops
                yawnStartTime = nil
                hasNotifiedYawn = false
                yawningStrike = 0
                yawningLastStrikeTime = nil
            }
            
            // MARK: - Position Tracking
            if let calibratedPos = calibratedNosePosition {
                // Get current nose position in world space
                let noseVertex = faceAnchor.geometry.vertices[9]
                let localPoint4 = SIMD4<Float>(noseVertex.x, noseVertex.y, noseVertex.z, 1.0)
                let worldPoint4 = faceAnchor.transform * localPoint4
                let currentWorldPos = SIMD3<Float>(worldPoint4.x, worldPoint4.y, worldPoint4.z)
                
                // Calculate offset from calibrated position
                let offset = currentWorldPos - calibratedPos
                
                // Normalize by threshold radius for UI display (-1 to 1)
                let normalizedX = offset.x / thresholdRadius
                let normalizedY = offset.y / thresholdRadius
                
                // Update UI state
                DispatchQueue.main.async {
                    self.eyeState.noseOffsetX = normalizedX
                    self.eyeState.noseOffsetY = -normalizedY // Invert Y for screen coordinates
                }
                
                // Calculate distance from calibrated position
                let distance = simd_distance(currentWorldPos, calibratedPos)
                let isOutside = distance > thresholdRadius

                // MARK: - Looking Away Detection with Strike System
                // Skip if phone pickup is active or during calibration
                if isOutside && !isPhonePickupActive && shouldRunDetection {
                    if outsideCircleStartTime == nil {
                        outsideCircleStartTime = Date()
                        hasNotifiedOutside = false
                        print("👀 [Detection] Looking away - starting timer")
                    } else {
                        if let startTime = outsideCircleStartTime {
                            let elapsed = Date().timeIntervalSince(startTime)

                            // Strike 1: Initial warning after outsideCircleDuration (2 seconds)
                            if elapsed >= outsideCircleDuration && lookingAwayStrike == 0 {
                                print("⚠️ [Strike 1] Looking away for \(elapsed)s - TRIGGERING ALERT")
                                self.playAlert("looking_away", strike: 1)
                                lookingAwayStrike = 1
                                lookingAwayLastStrikeTime = Date()
                            }
                            // Strike 2: Escalated warning after strikeDuration more seconds
                            else if lookingAwayStrike == 1,
                                    let lastStrikeTime = lookingAwayLastStrikeTime,
                                    Date().timeIntervalSince(lastStrikeTime) >= strikeDuration {
                                self.playAlert("looking_away_strike2", strike: 2)
                                lookingAwayStrike = 2
                                lookingAwayLastStrikeTime = Date()
                            }
                            // Note: Emergency call removed from Strike 3 - now triggered by FatigueTracker critical level
                        }
                    }
                } else {
                    // Reset when looking back at road
                    outsideCircleStartTime = nil
                    hasNotifiedOutside = false
                    lookingAwayStrike = 0
                    lookingAwayLastStrikeTime = nil
                }
            }

            // MARK: - Phone Pickup Detection (Z-Distance)
            // Only check if calibrated, not in calibration mode, and baseline Z is valid
            if shouldRunDetection && calibratedZDistance > 0 {
                checkPhonePickup(faceAnchor: faceAnchor)
            }
        }

        /// Detects if user picked up phone by checking if face is significantly closer than baseline
        private func checkPhonePickup(faceAnchor: ARFaceAnchor) {
            // Get current Z distance from face to camera
            let facePosition = faceAnchor.transform.columns.3
            let currentZDistance = abs(facePosition.z)

            // Calculate percentage closer compared to baseline
            let distanceChange = calibratedZDistance - currentZDistance
            let percentCloser = calibratedZDistance > 0 ? distanceChange / calibratedZDistance : 0

            // Check if face is significantly closer (user moved phone closer to face)
            let isCloser = percentCloser > phonePickupThresholdPercent

            // Set flag to suppress other alerts when phone pickup is active
            isPhonePickupActive = isCloser

            if isCloser {
                // Start tracking when face first gets too close
                if phonePickupStartTime == nil {
                    phonePickupStartTime = Date()
                    hasNotifiedPhonePickup = false
                    print("📱 [Detection] Face getting closer - Z: \(currentZDistance * 100)cm (baseline: \(calibratedZDistance * 100)cm, \(Int(percentCloser * 100))% closer)")
                } else {
                    if let startTime = phonePickupStartTime {
                        let elapsed = Date().timeIntervalSince(startTime)

                        // Trigger alert if close for minimum duration and not on cooldown
                        if elapsed >= phonePickupMinDuration && !hasNotifiedPhonePickup {
                            // Check cooldown
                            let canAlert: Bool
                            if let lastAlert = phonePickupLastAlertTime {
                                canAlert = Date().timeIntervalSince(lastAlert) >= phonePickupCooldown
                            } else {
                                canAlert = true
                            }

                            if canAlert {
                                print("⚠️ [Phone Pickup] User picked up phone! Z: \(currentZDistance * 100)cm (baseline: \(calibratedZDistance * 100)cm, \(Int(percentCloser * 100))% closer)")
                                hasNotifiedPhonePickup = true
                                phonePickupLastAlertTime = Date()

                                // Increment counter and log
                                DispatchQueue.main.async {
                                    self.eyeState.phonePickupCount += 1
                                    print("📊 [Phone Pickup] Count incremented to: \(self.eyeState.phonePickupCount)")
                                }

                                // Play phone pickup voice warning (no strike system)
                                playPhonePickupWarning()
                            }
                        }
                    }
                }
            } else {
                // Reset when face returns to normal distance
                phonePickupStartTime = nil
                hasNotifiedPhonePickup = false
            }
        }

        /// Plays a voice warning for phone pickup (no strike escalation)
        private func playPhonePickupWarning() {
            // Try to play phone_pickup audio file, fall back to system sound
            if let player = audioPlayers["phone_pickup"] {
                player.currentTime = 0
                player.play()
            } else {
                // Fallback: play a simple alert sound
                AudioServicesPlaySystemSound(1520) // Haptic feedback
            }
        }
    }

    static func dismantleUIView(_ uiView: ARSCNView, coordinator: Coordinator) {
        uiView.session.pause()
    }
}

// MARK: - Position Indicator View
struct PositionIndicatorView: View {
    let offsetX: CGFloat
    let offsetY: CGFloat

    private let circleSize: CGFloat = 56
    private let ballSize: CGFloat = 10

    // Success green color
    private let successColor = Color(red: 0.063, green: 0.725, blue: 0.506) // AppColors.success

    var body: some View {
        ZStack {
            // Outer circle background
            Circle()
                .fill(Color.black.opacity(0.4))
                .frame(width: circleSize, height: circleSize)
                .overlay(
                    Circle()
                        .stroke(Color.white.opacity(0.2), lineWidth: 1)
                )

            // Center reference (small dot)
            Circle()
                .fill(Color.white.opacity(0.3))
                .frame(width: 4, height: 4)

            // Moving ball (nose position)
            Circle()
                .fill(successColor)
                .frame(width: ballSize, height: ballSize)
                .shadow(color: successColor.opacity(0.6), radius: 4)
                .offset(
                    x: offsetX * (circleSize / 2 - ballSize / 2),
                    y: offsetY * (circleSize / 2 - ballSize / 2)
                )
                .animation(.spring(response: 0.3, dampingFraction: 0.7), value: offsetX)
                .animation(.spring(response: 0.3, dampingFraction: 0.7), value: offsetY)
        }
        .frame(width: circleSize, height: circleSize)
    }
}
