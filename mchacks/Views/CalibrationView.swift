//
//  CalibrationView.swift
//  mchacks
//
//  Waze-style calibration flow
//

import SwiftUI
import ARKit
import AVFoundation

struct CalibrationView: View {
    @Binding var isPresented: Bool
    @ObservedObject var eyeState: EyeTrackingState
    let onCalibrated: () -> Void

    @StateObject private var permissionManager = PermissionManager()
    @State private var showPermissionAlert = false
    @State private var isRequestingPermission = false
    @State private var hasStartedCalibration = false
    @State private var showSuccessEffect = false
    @State private var isCountingDown = false
    @State private var countdownValue = 3

    var body: some View {
        ZStack {
            // Dark background
            AppColors.backgroundPrimary
                .ignoresSafeArea()

            if !permissionManager.isCameraAuthorized && !isRequestingPermission {
                permissionRequestView
            } else {
                calibrationContentView
            }

            // Success overlay
            if showSuccessEffect {
                SuccessOverlay()
                    .ignoresSafeArea()
            }
        }
        .alert("Camera Permission Required", isPresented: $showPermissionAlert) {
            Button("Settings") {
                permissionManager.openSettings()
            }
            Button("Cancel", role: .cancel) {
                isPresented = false
            }
        } message: {
            Text("Please enable camera access in Settings to use face tracking.")
        }
        .onAppear {
            permissionManager.checkAllPermissions()
            if permissionManager.isCameraAuthorized && !hasStartedCalibration {
                startCalibration()
            }
        }
        .onChange(of: permissionManager.isCameraAuthorized) { _, authorized in
            if authorized && !hasStartedCalibration {
                startCalibration()
            }
        }
        .onChange(of: eyeState.isCalibrated) { _, calibrated in
            if calibrated {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                    showSuccessEffect = true
                }
                let generator = UINotificationFeedbackGenerator()
                generator.notificationOccurred(.success)

                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    onCalibrated()
                    isPresented = false
                }
            }
        }
        .onChange(of: eyeState.calibrationStep) { _, newStep in
            if newStep == 2 {
                isCountingDown = false
            }
        }
    }

    // MARK: - Permission Request View
    private var permissionRequestView: some View {
        VStack(spacing: 0) {
            // Close button
            HStack {
                Spacer()
                Button(action: { isPresented = false }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(AppColors.textSecondary)
                        .frame(width: 36, height: 36)
                        .background(AppColors.backgroundCard)
                        .clipShape(Circle())
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)

            Spacer()

            // Camera icon
            ZStack {
                Circle()
                    .fill(AppColors.backgroundCard)
                    .frame(width: 120, height: 120)

                Image(systemName: "camera.fill")
                    .font(.system(size: 44))
                    .foregroundColor(AppColors.accent)
            }

            Spacer().frame(height: 32)

            // Title and description
            VStack(spacing: 12) {
                Text("Camera Access")
                    .font(.system(size: 26, weight: .bold))
                    .foregroundColor(AppColors.textPrimary)

                Text("We need camera access to track your face and keep you safe while driving.")
                    .font(.system(size: 16))
                    .foregroundColor(AppColors.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }

            Spacer()

            // Enable button
            Button(action: {
                isRequestingPermission = true
                Task {
                    let granted = await permissionManager.requestCameraPermission()
                    if !granted {
                        showPermissionAlert = true
                    }
                    isRequestingPermission = false
                }
            }) {
                Text("Enable Camera")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 18)
                    .background(AppColors.accent)
                    .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 50)
        }
    }

    // MARK: - Calibration Content View
    private var calibrationContentView: some View {
        GeometryReader { geometry in
            ZStack {
                // Full screen AR Face View
                VStack(spacing: 0) {
                    if permissionManager.isCameraAuthorized {
                        ARFaceTrackingView(eyeState: eyeState)
                            .frame(
                                width: geometry.size.width,
                                height: geometry.size.height
                            )
                    } else {
                        AppColors.backgroundCard
                            .overlay(
                                ProgressView()
                                    .tint(AppColors.accent)
                                    .scaleEffect(1.5)
                            )
                    }
                }

                // Overlay content on top of camera
                VStack(spacing: 0) {
                    // Top instruction text
                    VStack(spacing: 12) {
                        Text(headerTitle)
                            .font(.system(size: 32, weight: .heavy))
                            .foregroundColor(.white)
                            .shadow(color: .black.opacity(0.7), radius: 8, x: 0, y: 4)

                        Text(headerSubtitle)
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(.white.opacity(0.9))
                            .shadow(color: .black.opacity(0.7), radius: 6, x: 0, y: 3)
                    }
                    .padding(.top, geometry.safeAreaInsets.top + 30)

                    Spacer()

                    // Countdown in the center (overlaid on camera)
                    if isCountingDown {
                        CountdownOverlay(value: countdownValue)
                    } else if eyeState.calibrationStep == 1 {
                        // Face guide overlay
                        FaceGuideOverlay(isStable: eyeState.isPositionStable)
                            .frame(width: geometry.size.width, height: geometry.size.height * 0.5)
                    }

                    Spacer()

                    // Bottom section with progress bar
                    VStack(spacing: 16) {
                        // Progress bar
                        CalibrationProgressBar(progress: CGFloat(eyeState.calibrationProgress))
                            .padding(.horizontal, 40)

                        // Instruction text
                        Text(instructionText)
                            .font(.system(size: 15, weight: .medium))
                            .foregroundColor(.white.opacity(0.9))
                            .shadow(color: .black.opacity(0.5), radius: 4, x: 0, y: 2)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 40)
                    }
                    .padding(.bottom, geometry.safeAreaInsets.bottom + 40)
                }

                // Blink counter overlay (bottom right)
                if eyeState.calibrationStep == 2 {
                    BlinkCounterOverlay()
                }
            }
        }
        .ignoresSafeArea()
        .onAppear {
            // Auto-start countdown immediately
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                if !isCountingDown && eyeState.calibrationStep == 1 {
                    startCountdown()
                }
            }
        }
    }

    // MARK: - Computed Properties
    private var headerTitle: String {
        if isCountingDown {
            return ""
        }
        switch eyeState.calibrationStep {
        case 1: return "Position your face"
        case 2: return "Blink naturally"
        case 3: return "All set!"
        default: return "Calibrating"
        }
    }

    private var headerSubtitle: String {
        if isCountingDown {
            return "Hold still..."
        }
        switch eyeState.calibrationStep {
        case 1: return "Center your face in the frame"
        case 2: return "Learning your blink pattern"
        case 3: return "Starting your trip"
        default: return ""
        }
    }

    private var borderColor: Color {
        if isCountingDown { return AppColors.success }
        switch eyeState.calibrationStep {
        case 1: return eyeState.isPositionStable ? AppColors.success : AppColors.accent
        case 2: return AppColors.accent
        case 3: return AppColors.success
        default: return AppColors.accent
        }
    }

    private var instructionText: String {
        if isCountingDown {
            return "Capturing your position..."
        }
        switch eyeState.calibrationStep {
        case 1: return "Center your face in the frame"
        case 2: return "Just blink normally for a few seconds"
        case 3: return "You're all set to drive safely!"
        default: return ""
        }
    }

    private func startCalibration() {
        hasStartedCalibration = true
        eyeState.resetCalibrationState()
        NotificationCenter.default.post(name: NSNotification.Name("StartCalibration"), object: nil)
    }

    private func startCountdown() {
        isCountingDown = true
        countdownValue = 3

        NotificationCenter.default.post(name: NSNotification.Name("StartPositionCapture"), object: nil)

        Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { timer in
            if countdownValue > 1 {
                countdownValue -= 1
            } else {
                timer.invalidate()
            }
        }
    }
}

// MARK: - Progress Bar
struct CalibrationProgressBar: View {
    let progress: CGFloat

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                // Background
                RoundedRectangle(cornerRadius: 4)
                    .fill(AppColors.backgroundCard)
                    .frame(height: 6)

                // Progress
                RoundedRectangle(cornerRadius: 4)
                    .fill(AppColors.accent)
                    .frame(width: geometry.size.width * progress, height: 6)
                    .animation(.easeInOut(duration: 0.3), value: progress)
            }
        }
        .frame(height: 6)
    }
}

// MARK: - Face Guide Overlay
struct FaceGuideOverlay: View {
    let isStable: Bool
    @State private var pulseScale: CGFloat = 1.0

    var body: some View {
        ZStack {
            // Face outline guide
            RoundedRectangle(cornerRadius: 80, style: .continuous)
                .stroke(
                    isStable ? AppColors.success : Color.white.opacity(0.6),
                    style: StrokeStyle(lineWidth: 4, dash: isStable ? [] : [15, 12])
                )
                .frame(width: 180, height: 240)
                .scaleEffect(pulseScale)
                .shadow(color: (isStable ? AppColors.success : AppColors.accent).opacity(0.3), radius: 10)
                .onAppear {
                    if !isStable {
                        withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
                            pulseScale = 1.05
                        }
                    }
                }
                .onChange(of: isStable) { _, stable in
                    if stable {
                        withAnimation(.easeOut(duration: 0.3)) {
                            pulseScale = 1.0
                        }
                    }
                }
        }
    }
}

// MARK: - Blink Counter Overlay
struct BlinkCounterOverlay: View {
    @State private var eyeScale: CGFloat = 1.0
    @State private var glowOpacity: Double = 0.3

    var body: some View {
        VStack {
            Spacer()
            HStack {
                Spacer()
                ZStack {
                    // Glow effect
                    Circle()
                        .fill(AppColors.accent.opacity(glowOpacity))
                        .frame(width: 70, height: 70)

                    Circle()
                        .fill(AppColors.accent)
                        .frame(width: 56, height: 56)
                        .shadow(color: AppColors.accent.opacity(0.5), radius: 10)

                    Image(systemName: "eye")
                        .font(.system(size: 26, weight: .medium))
                        .foregroundColor(.black)
                        .scaleEffect(eyeScale)
                }
                .padding(24)
                .onAppear {
                    withAnimation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true)) {
                        eyeScale = 0.85
                    }
                    withAnimation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true)) {
                        glowOpacity = 0.6
                    }
                }
            }
        }
        .padding(.bottom, 80)
    }
}

// MARK: - Countdown Overlay
struct CountdownOverlay: View {
    let value: Int
    @State private var scale: CGFloat = 0.5
    @State private var opacity: Double = 0
    @State private var ringScale: CGFloat = 0.8
    @State private var ringOpacity: Double = 1.0

    var body: some View {
        ZStack {
            // Animated ring pulse
            Circle()
                .stroke(AppColors.accent.opacity(0.3), lineWidth: 8)
                .frame(width: 180, height: 180)
                .scaleEffect(ringScale)
                .opacity(ringOpacity)

            Circle()
                .stroke(AppColors.accent.opacity(0.5), lineWidth: 4)
                .frame(width: 160, height: 160)
                .scaleEffect(ringScale * 0.9)
                .opacity(ringOpacity)

            // Background circle
            Circle()
                .fill(Color.black.opacity(0.6))
                .frame(width: 140, height: 140)
                .scaleEffect(scale)

            // Accent ring
            Circle()
                .stroke(AppColors.accent, lineWidth: 6)
                .frame(width: 140, height: 140)
                .scaleEffect(scale)

            // Number
            Text("\(value)")
                .font(.system(size: 80, weight: .bold, design: .rounded))
                .foregroundColor(AppColors.accent)
                .scaleEffect(scale)
                .shadow(color: AppColors.accent.opacity(0.5), radius: 20, x: 0, y: 0)
        }
        .onAppear {
            // Pop in animation
            withAnimation(.spring(response: 0.4, dampingFraction: 0.6)) {
                scale = 1.0
                opacity = 1.0
            }
            // Ring pulse animation
            withAnimation(.easeOut(duration: 0.8).repeatForever(autoreverses: false)) {
                ringScale = 1.5
                ringOpacity = 0
            }
        }
        .onChange(of: value) { _, _ in
            // Reset and animate on each number change
            scale = 0.5
            withAnimation(.spring(response: 0.3, dampingFraction: 0.5)) {
                scale = 1.0
            }
            // Haptic feedback
            let generator = UIImpactFeedbackGenerator(style: .medium)
            generator.impactOccurred()
        }
    }
}

// MARK: - Success Overlay
struct SuccessOverlay: View {
    @State private var scale: CGFloat = 0.5
    @State private var opacity: Double = 0
    @State private var ringPulse: CGFloat = 1.0

    var body: some View {
        ZStack {
            // Dim background
            Color.black.opacity(0.85)

            VStack(spacing: 32) {
                ZStack {
                    // Outer pulsing ring
                    Circle()
                        .stroke(AppColors.accent.opacity(0.2), lineWidth: 3)
                        .frame(width: 180, height: 180)
                        .scaleEffect(ringPulse)

                    // Glow rings
                    Circle()
                        .fill(AppColors.accent.opacity(0.15))
                        .frame(width: 160, height: 160)
                        .scaleEffect(scale * 1.3)

                    Circle()
                        .fill(AppColors.accent.opacity(0.1))
                        .frame(width: 120, height: 120)
                        .scaleEffect(scale * 1.1)

                    // Icon
                    ZStack {
                        Circle()
                            .fill(AppColors.accent)
                            .frame(width: 100, height: 100)
                            .shadow(color: AppColors.accent.opacity(0.6), radius: 20)

                        Image(systemName: "checkmark")
                            .font(.system(size: 44, weight: .bold))
                            .foregroundColor(.black)
                    }
                    .scaleEffect(scale)
                }

                Text("You're all set!")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundColor(.white)
                    .opacity(opacity)
            }
        }
        .onAppear {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) {
                scale = 1.0
            }
            withAnimation(.easeOut(duration: 0.3).delay(0.2)) {
                opacity = 1.0
            }
            withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
                ringPulse = 1.15
            }
        }
    }
}
