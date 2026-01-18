//
//  FatigueTracker.swift
//  mchacks
//
//  Comprehensive fatigue detection using weighted multi-signal fusion
//

import Foundation
import Combine
import simd

// MARK: - Fatigue Level Enum
enum FatigueLevel: String, CaseIterable {
    case normal = "Normal"
    case mild = "Mild Fatigue"
    case moderate = "Moderate Fatigue"
    case high = "High Fatigue"
    case critical = "Critical"
    
    var color: String {
        switch self {
        case .normal: return "green"
        case .mild: return "yellow"
        case .moderate: return "orange"
        case .high: return "red"
        case .critical: return "purple"
        }
    }
    
    var shouldAlert: Bool {
        switch self {
        case .normal, .mild: return false
        case .moderate, .high, .critical: return true
        }
    }
    
    var alertPriority: Int {
        switch self {
        case .normal: return 0
        case .mild: return 1
        case .moderate: return 2
        case .high: return 3
        case .critical: return 4
        }
    }
}

// MARK: - Blink Event
struct BlinkEvent {
    let startTime: Date
    let endTime: Date
    var duration: TimeInterval { endTime.timeIntervalSince(startTime) }
}

// MARK: - Head Nod Event
struct HeadNodEvent {
    let timestamp: Date
    let pitchDrop: Float  // How much the head dropped (degrees)
    let recoveryTime: TimeInterval  // How fast they recovered
}

// MARK: - Yawn Event
struct YawnEvent {
    let timestamp: Date
    let duration: TimeInterval
}

// MARK: - Fatigue Metrics (Published for UI)
class FatigueMetrics: ObservableObject {
    @Published var perclos: Float = 0  // 0-100%
    @Published var longBlinkRate: Float = 0  // per minute
    @Published var meanBlinkDuration: TimeInterval = 0  // seconds
    @Published var headNodRate: Float = 0  // per 5 minutes
    @Published var yawnRate: Float = 0  // per 5 minutes
    @Published var yawnCount: Int = 0  // total yawns during trip
    @Published var gazeDeviationPercent: Float = 0  // % time looking away

    @Published var fatigueScore: Float = 0  // 0-100 composite
    @Published var fatigueLevel: FatigueLevel = .normal

    @Published var lastAlertTime: Date?
    @Published var alertCooldownActive: Bool = false

    // PERCLOS history for graph (sampled every 10 seconds)
    @Published var perclosHistory: [Float] = []
}

// MARK: - Fatigue Tracker
class FatigueTracker: ObservableObject {
    
    // MARK: - Published Metrics
    @Published var metrics = FatigueMetrics()
    
    // MARK: - Configuration
    struct Config {
        // Window sizes
        var perclosWindowSeconds: TimeInterval = 60  // PERCLOS calculated over 60s
        var blinkHistoryCount: Int = 50  // Keep last 50 blinks for analysis
        var headNodWindowMinutes: TimeInterval = 5
        var yawnWindowMinutes: TimeInterval = 5
        var gazeWindowSeconds: TimeInterval = 60
        
        // Thresholds
        var eyeClosedThreshold: Float = 0.6  // Eye blink value > 0.6 = closed
        var longBlinkThreshold: TimeInterval = 0.4  // Blinks > 400ms are "long"
        var veryLongBlinkThreshold: TimeInterval = 0.8  // Blinks > 800ms are concerning
        var yawnJawThreshold: Float = 0.7  // Jaw open > 0.7 = potential yawn
        var yawnMinDuration: TimeInterval = 1.5  // Must be sustained for 1.5s
        var gazeDeviationThreshold: Float = 1.5  // Normalized offset > 1.5 = looking away (allows normal mirror checks)
        var gazeForgivenessSeconds: TimeInterval = 1.5  // Brief glances < 1.5s forgiven
        
        // Head nod detection
        var headNodPitchThreshold: Float = 10  // Degrees of pitch drop
        var headNodRecoveryThreshold: TimeInterval = 0.5  // Quick recovery = nod
        
        // Alert configuration
        var alertCooldownSeconds: TimeInterval = 30  // Min time between alerts
        
        // Weights for composite score
        var perclosWeight: Float = 0.40
        var longBlinkWeight: Float = 0.20
        var headNodWeight: Float = 0.15
        var yawnWeight: Float = 0.10
        var gazeWeight: Float = 0.10
        var meanBlinkDurationWeight: Float = 0.05
        
        // Score thresholds for fatigue levels
        var mildThreshold: Float = 30
        var moderateThreshold: Float = 55  // Increased - moderate should require sustained fatigue signs
        var highThreshold: Float = 70
        var criticalThreshold: Float = 85
    }
    
    var config = Config()
    
    // MARK: - Internal State
    
    // Eye closure tracking (for PERCLOS)
    private var eyeClosureHistory: [(timestamp: Date, isClosed: Bool)] = []
    
    // Blink tracking
    private var blinkHistory: [BlinkEvent] = []
    private var currentBlinkStart: Date?
    private var wasEyeClosed: Bool = false
    
    // Head tracking
    private var headPitchHistory: [(timestamp: Date, pitch: Float)] = []
    private var headNodEvents: [HeadNodEvent] = []
    private var potentialNodStart: (timestamp: Date, pitch: Float)?
    private var baselinePitch: Float?
    
    // Yawn tracking
    private var yawnEvents: [YawnEvent] = []
    private var currentYawnStart: Date?
    private var wasYawning: Bool = false
    
    // Gaze tracking
    private var gazeHistory: [(timestamp: Date, isDeviated: Bool)] = []
    private var currentGazeDeviationStart: Date?
    
    // MARK: - Acute Danger Tracking (Immediate danger signals)
    private var eyesClosedSince: Date?  // When did eyes close (for immediate danger)
    private var lookingAwaySince: Date?  // When did they start looking away
    private var headDroppedSince: Date?  // When did head drop significantly
    
    // Frame rate estimation
    private var lastUpdateTime: Date?
    private var frameCount: Int = 0
    private var estimatedFPS: Float = 60

    // PERCLOS history sampling
    private var lastPerclosSampleTime: Date?
    private let perclosSampleInterval: TimeInterval = 10.0  // Sample every 10 seconds
    
    // MARK: - Calibration
    private var isCalibrated: Bool = false
    private var isCalibrating: Bool = false  // Track if we've started calibration
    private var calibrationSamples: [(leftEye: Float, rightEye: Float, pitch: Float)] = []
    private let calibrationSampleCount = 120  // ~2 seconds at 60fps
    
    // Baseline values (set during calibration)
    private var baselineEyeOpenness: Float = 0.2  // Default, will be calibrated
    
    // MARK: - Initialization
    
    init() {
        // Start with default config
    }
    
    // MARK: - Main Update Function
    
    /// Call this every frame with the latest face tracking data
    func update(
        leftEyeBlink: Float,      // 0 = open, 1 = closed
        rightEyeBlink: Float,
        headPitch: Float,          // Degrees, negative = looking down
        jawOpen: Float,            // 0 = closed, 1 = open
        noseOffsetX: Float,        // Normalized -1 to 1+
        noseOffsetY: Float,
        isCalibrated: Bool
    ) {
        let now = Date()
        
        // Update FPS estimation
        updateFrameRate(now: now)
        
        // Handle calibration phase
        if !self.isCalibrated && isCalibrated && !isCalibrating {
            // User just calibrated their nose position, start collecting baseline for fatigue tracking
            print("🎯 [FatigueTracker] Starting calibration (nose calibrated)")
            startCalibration()
        }
        
        if !self.isCalibrated {
            if isCalibrating {
                collectCalibrationSample(leftEyeBlink: leftEyeBlink, rightEyeBlink: rightEyeBlink, pitch: headPitch)
            }
            return
        }
        
        // Process all signals
        let avgEyeBlink = (leftEyeBlink + rightEyeBlink) / 2.0
        let isClosed = avgEyeBlink > config.eyeClosedThreshold
        
        updateEyeClosure(isClosed: isClosed, now: now)
        updateBlinkTracking(isClosed: isClosed, avgBlink: avgEyeBlink, now: now)
        updateHeadTracking(pitch: headPitch, now: now)
        updateYawnTracking(jawOpen: jawOpen, now: now)
        updateGazeTracking(offsetX: noseOffsetX, offsetY: noseOffsetY, now: now)
        
        // Cleanup old data
        cleanupOldData(now: now)
        
        // Calculate all metrics
        calculateMetrics(now: now)
        
        // Calculate composite fatigue score
        calculateFatigueScore()
        
        // Determine fatigue level
        updateFatigueLevel()
        
        // Debug: Log every 60 frames (~1 second)
        if frameCount % 60 == 0 {
            print("📊 [FatigueTracker] PERCLOS: \(String(format: "%.1f", metrics.perclos))%, Score: \(String(format: "%.0f", metrics.fatigueScore)), Level: \(metrics.fatigueLevel.rawValue), EyeHistory: \(eyeClosureHistory.count) frames")
        }
    }
    
    // MARK: - Calibration
    
    private func startCalibration() {
        calibrationSamples = []
        isCalibrating = true
    }
    
    private func collectCalibrationSample(leftEyeBlink: Float, rightEyeBlink: Float, pitch: Float) {
        calibrationSamples.append((leftEyeBlink, rightEyeBlink, pitch))
        
        // Log progress every 30 samples
        if calibrationSamples.count % 30 == 0 {
            print("⏳ [FatigueTracker] Calibrating... \(calibrationSamples.count)/\(calibrationSampleCount) samples")
        }
        
        if calibrationSamples.count >= calibrationSampleCount {
            finalizeCalibration()
        }
    }
    
    private func finalizeCalibration() {
        // Calculate baseline eye openness (average when alert)
        let avgBlinks = calibrationSamples.map { ($0.leftEye + $0.rightEye) / 2.0 }
        baselineEyeOpenness = avgBlinks.reduce(0, +) / Float(avgBlinks.count)
        
        // Calculate baseline head pitch
        let avgPitch = calibrationSamples.map { $0.pitch }.reduce(0, +) / Float(calibrationSamples.count)
        baselinePitch = avgPitch
        
        isCalibrated = true
        isCalibrating = false
        print("✅ [FatigueTracker] Calibration complete! Baseline eye: \(String(format: "%.2f", baselineEyeOpenness)), baseline pitch: \(String(format: "%.1f", avgPitch))°")
        print("✅ [FatigueTracker] Now tracking fatigue metrics...")
    }
    
    // MARK: - Frame Rate
    
    private func updateFrameRate(now: Date) {
        frameCount += 1
        
        if let last = lastUpdateTime {
            let elapsed = now.timeIntervalSince(last)
            if elapsed >= 1.0 {
                estimatedFPS = Float(frameCount) / Float(elapsed)
                frameCount = 0
                lastUpdateTime = now
            }
        } else {
            lastUpdateTime = now
        }
    }
    
    // MARK: - Eye Closure (PERCLOS + Acute)
    
    private func updateEyeClosure(isClosed: Bool, now: Date) {
        eyeClosureHistory.append((timestamp: now, isClosed: isClosed))
        
        // Track acute danger: eyes closed right now
        if isClosed {
            if eyesClosedSince == nil {
                eyesClosedSince = now
            }
        } else {
            eyesClosedSince = nil
        }
    }
    
    // MARK: - Blink Tracking
    
    private func updateBlinkTracking(isClosed: Bool, avgBlink: Float, now: Date) {
        if isClosed && !wasEyeClosed {
            // Blink started
            currentBlinkStart = now
        } else if !isClosed && wasEyeClosed {
            // Blink ended
            if let start = currentBlinkStart {
                let blink = BlinkEvent(startTime: start, endTime: now)
                
                // Only count as blink if duration is reasonable (50ms - 2s)
                if blink.duration >= 0.05 && blink.duration <= 2.0 {
                    blinkHistory.append(blink)
                    
                    // Trim to max count
                    if blinkHistory.count > config.blinkHistoryCount {
                        blinkHistory.removeFirst()
                    }
                }
            }
            currentBlinkStart = nil
        }
        
        wasEyeClosed = isClosed
    }
    
    // MARK: - Head Tracking (Nod Detection + Acute)
    
    private func updateHeadTracking(pitch: Float, now: Date) {
        headPitchHistory.append((timestamp: now, pitch: pitch))
        
        guard let baseline = baselinePitch else { return }
        
        let pitchDelta = baseline - pitch  // Positive = looking down from baseline
        
        if pitchDelta > config.headNodPitchThreshold {
            // Head is dropped - potential nod start
            if potentialNodStart == nil {
                potentialNodStart = (timestamp: now, pitch: pitch)
            }
            
            // Track acute danger: head currently dropped
            if headDroppedSince == nil {
                headDroppedSince = now
            }
        } else if let nodStart = potentialNodStart {
            // Head recovered - check if it was a nod
            let recoveryTime = now.timeIntervalSince(nodStart.timestamp)
            
            if recoveryTime < config.headNodRecoveryThreshold && recoveryTime > 0.1 {
                // Quick recovery = fatigue nod
                let nodEvent = HeadNodEvent(
                    timestamp: now,
                    pitchDrop: baseline - nodStart.pitch,
                    recoveryTime: recoveryTime
                )
                headNodEvents.append(nodEvent)
            }
            potentialNodStart = nil
            headDroppedSince = nil  // Head recovered
        } else {
            headDroppedSince = nil  // Head is up
        }
    }
    
    // MARK: - Yawn Tracking
    
    private func updateYawnTracking(jawOpen: Float, now: Date) {
        let isYawning = jawOpen > config.yawnJawThreshold
        
        if isYawning && !wasYawning {
            // Potential yawn started
            currentYawnStart = now
        } else if !isYawning && wasYawning {
            // Yawn ended
            if let start = currentYawnStart {
                let duration = now.timeIntervalSince(start)
                
                // Only count if sustained long enough
                if duration >= config.yawnMinDuration {
                    let yawn = YawnEvent(timestamp: now, duration: duration)
                    yawnEvents.append(yawn)
                }
            }
            currentYawnStart = nil
        }
        
        wasYawning = isYawning
    }
    
    // MARK: - Gaze Tracking (+ Acute)
    
    private func updateGazeTracking(offsetX: Float, offsetY: Float, now: Date) {
        let offsetMagnitude = sqrt(offsetX * offsetX + offsetY * offsetY)
        let isDeviated = offsetMagnitude > config.gazeDeviationThreshold
        
        if isDeviated && currentGazeDeviationStart == nil {
            // Started looking away
            currentGazeDeviationStart = now
        } else if !isDeviated && currentGazeDeviationStart != nil {
            // Stopped looking away
            currentGazeDeviationStart = nil
        }
        
        gazeHistory.append((timestamp: now, isDeviated: isDeviated))
        
        // Track acute danger: looking away right now
        if isDeviated {
            if lookingAwaySince == nil {
                lookingAwaySince = now
            }
        } else {
            lookingAwaySince = nil
        }
    }
    
    // MARK: - Cleanup Old Data
    
    private func cleanupOldData(now: Date) {
        let perclosWindow = now.addingTimeInterval(-config.perclosWindowSeconds)
        let headNodWindow = now.addingTimeInterval(-config.headNodWindowMinutes * 60)
        let yawnWindow = now.addingTimeInterval(-config.yawnWindowMinutes * 60)
        let gazeWindow = now.addingTimeInterval(-config.gazeWindowSeconds)
        
        eyeClosureHistory.removeAll { $0.timestamp < perclosWindow }
        headPitchHistory.removeAll { $0.timestamp < perclosWindow }
        headNodEvents.removeAll { $0.timestamp < headNodWindow }
        yawnEvents.removeAll { $0.timestamp < yawnWindow }
        gazeHistory.removeAll { $0.timestamp < gazeWindow }
    }
    
    // MARK: - Calculate Metrics

    private func calculateMetrics(now: Date) {
        // PERCLOS: % of frames with eyes closed in window
        if !eyeClosureHistory.isEmpty {
            let closedCount = eyeClosureHistory.filter { $0.isClosed }.count
            let perclos = Float(closedCount) / Float(eyeClosureHistory.count) * 100

            DispatchQueue.main.async {
                self.metrics.perclos = perclos
            }

            // Sample PERCLOS for history graph every 10 seconds
            if lastPerclosSampleTime == nil || now.timeIntervalSince(lastPerclosSampleTime!) >= perclosSampleInterval {
                lastPerclosSampleTime = now
                DispatchQueue.main.async {
                    self.metrics.perclosHistory.append(perclos)
                }
            }
        }

        // Long blink rate: blinks > threshold per minute
        if !blinkHistory.isEmpty {
            let oneMinuteAgo = now.addingTimeInterval(-60)
            let recentBlinks = blinkHistory.filter { $0.endTime > oneMinuteAgo }
            let longBlinks = recentBlinks.filter { $0.duration > config.longBlinkThreshold }

            DispatchQueue.main.async {
                self.metrics.longBlinkRate = Float(longBlinks.count)
            }

            // Mean blink duration
            if !recentBlinks.isEmpty {
                let totalDuration = recentBlinks.reduce(0.0) { $0 + $1.duration }
                let meanDuration = totalDuration / Double(recentBlinks.count)

                DispatchQueue.main.async {
                    self.metrics.meanBlinkDuration = meanDuration
                }
            }
        }

        // Head nod rate per 5 minutes
        let nodRate = Float(headNodEvents.count) / Float(config.headNodWindowMinutes) * 5.0
        DispatchQueue.main.async {
            self.metrics.headNodRate = nodRate
        }

        // Yawn count and rate
        let yawnRate = Float(yawnEvents.count) / Float(config.yawnWindowMinutes) * 5.0
        DispatchQueue.main.async {
            self.metrics.yawnRate = yawnRate
            self.metrics.yawnCount = self.yawnEvents.count
        }
        
        // Gaze deviation percentage
        if !gazeHistory.isEmpty {
            let deviatedCount = gazeHistory.filter { $0.isDeviated }.count
            let gazeDeviation = Float(deviatedCount) / Float(gazeHistory.count) * 100
            
            DispatchQueue.main.async {
                self.metrics.gazeDeviationPercent = gazeDeviation
            }
        }
    }
    
    // MARK: - Calculate Composite Fatigue Score
    
    private func calculateFatigueScore() {
        let now = Date()
        
        // ===========================================
        // ACUTE DANGER CHECK (Immediate threats)
        // These can immediately spike the score to critical
        // ===========================================
        
        var acuteDangerScore: Float = 0
        
        // Eyes closed right now - VERY DANGEROUS
        if let closedSince = eyesClosedSince {
            let closedDuration = now.timeIntervalSince(closedSince)
            if closedDuration >= 3.0 {
                // Eyes closed 3+ seconds = CRITICAL (100)
                acuteDangerScore = max(acuteDangerScore, 100)
            } else if closedDuration >= 2.0 {
                // Eyes closed 2-3 seconds = HIGH (85)
                acuteDangerScore = max(acuteDangerScore, 85)
            } else if closedDuration >= 1.0 {
                // Eyes closed 1-2 seconds = MODERATE (60)
                acuteDangerScore = max(acuteDangerScore, 60)
            }
        }
        
        // Looking away right now - only dangerous after sustained periods
        // Brief glances (mirrors, speedometer) are normal driving behavior
        if let awaySince = lookingAwaySince {
            let awayDuration = now.timeIntervalSince(awaySince)
            if awayDuration >= 8.0 {
                // Looking away 8+ seconds = HIGH (75) - genuinely dangerous
                acuteDangerScore = max(acuteDangerScore, 75)
            } else if awayDuration >= 5.0 {
                // Looking away 5-8 seconds = mild concern (35)
                acuteDangerScore = max(acuteDangerScore, 35)
            }
            // Under 5 seconds = normal driving, no acute danger penalty
        }
        
        // Head dropped right now - DANGEROUS (indicates nodding off)
        if let droppedSince = headDroppedSince {
            let droppedDuration = now.timeIntervalSince(droppedSince)
            if droppedDuration >= 3.0 {
                // Head dropped 3+ seconds = HIGH (80) - likely nodding off
                acuteDangerScore = max(acuteDangerScore, 80)
            } else if droppedDuration >= 2.0 {
                // Head dropped 2-3 seconds = moderate concern (50)
                acuteDangerScore = max(acuteDangerScore, 50)
            }
            // Under 2 seconds could just be looking at something
        }
        
        // Currently yawning - mild concern
        if let yawnStart = currentYawnStart {
            let yawnDuration = now.timeIntervalSince(yawnStart)
            if yawnDuration >= 2.0 {
                acuteDangerScore = max(acuteDangerScore, 40)
            }
        }
        
        // ===========================================
        // TREND-BASED SCORE (Gradual fatigue buildup)
        // ===========================================
        
        // PERCLOS: Scale linearly up to 50%
        let perclosScore = min(metrics.perclos / 50.0, 1.0) * 100
        
        // Long blink rate: 15+ per minute is max
        let longBlinkScore = min(metrics.longBlinkRate / 15.0, 1.0) * 100
        
        // Mean blink duration: > 500ms is max
        let blinkDurationScore = min(Float(metrics.meanBlinkDuration) / 0.5, 1.0) * 100
        
        // Head nods: 6+ per 5 minutes is max
        let headNodScore = min(metrics.headNodRate / 6.0, 1.0) * 100
        
        // Yawns: 5+ per 5 minutes is max
        let yawnScore = min(metrics.yawnRate / 5.0, 1.0) * 100
        
        // Gaze deviation: 40%+ is max
        let gazeScore = min(metrics.gazeDeviationPercent / 40.0, 1.0) * 100
        
        // Weighted trend-based composite
        let trendScore = perclosScore * config.perclosWeight +
                        longBlinkScore * config.longBlinkWeight +
                        blinkDurationScore * config.meanBlinkDurationWeight +
                        headNodScore * config.headNodWeight +
                        yawnScore * config.yawnWeight +
                        gazeScore * config.gazeWeight
        
        // ===========================================
        // FINAL SCORE: Max of acute danger or trend
        // Acute danger can immediately spike to critical
        // ===========================================
        
        let finalScore = max(acuteDangerScore, trendScore)
        
        DispatchQueue.main.async {
            self.metrics.fatigueScore = finalScore
        }
    }
    
    // MARK: - Update Fatigue Level
    
    private func updateFatigueLevel() {
        let score = metrics.fatigueScore
        
        let level: FatigueLevel
        if score >= config.criticalThreshold {
            level = .critical
        } else if score >= config.highThreshold {
            level = .high
        } else if score >= config.moderateThreshold {
            level = .moderate
        } else if score >= config.mildThreshold {
            level = .mild
        } else {
            level = .normal
        }
        
        DispatchQueue.main.async {
            self.metrics.fatigueLevel = level
        }
    }
    
    // MARK: - Alert Management
    
    func shouldTriggerAlert() -> Bool {
        guard metrics.fatigueLevel.shouldAlert else { return false }
        
        // Check cooldown
        if let lastAlert = metrics.lastAlertTime {
            let elapsed = Date().timeIntervalSince(lastAlert)
            if elapsed < config.alertCooldownSeconds {
                return false
            }
        }
        
        return true
    }
    
    func markAlertTriggered() {
        DispatchQueue.main.async {
            self.metrics.lastAlertTime = Date()
            self.metrics.alertCooldownActive = true
            
            // Clear cooldown after delay
            DispatchQueue.main.asyncAfter(deadline: .now() + self.config.alertCooldownSeconds) {
                self.metrics.alertCooldownActive = false
            }
        }
    }
    
    // MARK: - Reset
    
    func reset() {
        eyeClosureHistory.removeAll()
        blinkHistory.removeAll()
        headPitchHistory.removeAll()
        headNodEvents.removeAll()
        yawnEvents.removeAll()
        gazeHistory.removeAll()
        
        currentBlinkStart = nil
        wasEyeClosed = false
        potentialNodStart = nil
        currentYawnStart = nil
        wasYawning = false
        currentGazeDeviationStart = nil
        
        // Reset acute danger tracking
        eyesClosedSince = nil
        lookingAwaySince = nil
        headDroppedSince = nil
        
        isCalibrated = false
        isCalibrating = false
        calibrationSamples.removeAll()
        baselinePitch = nil
        lastPerclosSampleTime = nil

        // Reset metrics values instead of creating new object
        // (Creating new object would break UI observation)
        DispatchQueue.main.async {
            self.metrics.perclos = 0
            self.metrics.longBlinkRate = 0
            self.metrics.meanBlinkDuration = 0
            self.metrics.headNodRate = 0
            self.metrics.yawnRate = 0
            self.metrics.yawnCount = 0
            self.metrics.gazeDeviationPercent = 0
            self.metrics.fatigueScore = 0
            self.metrics.fatigueLevel = .normal
            self.metrics.lastAlertTime = nil
            self.metrics.alertCooldownActive = false
            self.metrics.perclosHistory.removeAll()
        }

        print("🔄 [FatigueTracker] Reset complete")
    }
}
