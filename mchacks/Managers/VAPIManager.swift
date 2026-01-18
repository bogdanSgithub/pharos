//
//  VAPIManager.swift
//  mchacks
//

import Foundation
import Combine
import Vapi
import AVFoundation

class VAPIManager: ObservableObject {
    enum CallState {
        case started, loading, ended
    }

    @Published var callState: CallState = .ended
    @Published var callDuration: TimeInterval = 0
    @Published var isMuted = false

    var vapiEvents = [Vapi.Event]()
    private var cancellables = Set<AnyCancellable>()
    private var callTimer: Timer?
    private var callStartTime: Date?
    
    // Callbacks to pause/resume AR session
    var onCallWillStart: (() -> Void)?
    var onCallDidEnd: (() -> Void)?

    let vapi: Vapi
    private let publicKey = "3a3684e6-751e-4595-bac1-9d7c61bf4f8d"

    init() {
        vapi = Vapi(publicKey: publicKey)
    }

    func setupVapi() {
        vapi.eventPublisher
            .sink { [weak self] event in
                self?.vapiEvents.append(event)
                switch event {
                case .callDidStart:
                    print(">>> CALL DID START - configuring audio")
                    self?.callState = .started
                    self?.startCallTimer()
                    // Route audio to speaker after call connects
                    self?.configureAudioForSpeaker()
                case .callDidEnd:
                    self?.callState = .ended
                    self?.stopCallTimer()
                    // IMPORTANT: Resume AR session when call ends (whether user or AI ended it)
                    self?.onCallDidEnd?()
                case .speechUpdate:
                    print(event)
                case .conversationUpdate:
                    print(event)
                case .functionCall:
                    print(event)
                case .hang:
                    print(event)
                case .metadata:
                    print(event)
                case .transcript:
                    print(event)
                case .statusUpdate:
                    print(event)
                case .modelOutput:
                    print(event)
                case .userInterrupted:
                    print(event)
                case .voiceInput:
                    print(event)
                case .error(let error):
                    print("Error: \(error)")
                }
            }
            .store(in: &cancellables)
    }

    @MainActor
    func handleCallAction() async {
        if callState == .ended {
            await startCall()
        } else {
            endCall()
        }
    }

    @MainActor
    func startCall() async {
        callState = .loading
        
        // FIRST: Pause AR session to release audio session
        onCallWillStart?()

        // Wait for AR session to fully release (using notification instead of fixed delay)
        await waitForARSessionPause()
        print("AR session paused, starting Vapi call...")

        // Use Vapi's default voice configuration for better compatibility
        let assistant: [String: Any] = [
            "transcriber": [
                "provider": "deepgram",
                "model": "nova-2",
                "language": "en"
            ],
            "model": [
                "provider": "openai",
                "model": "gpt-4o-mini",
                "messages": [
                    ["role": "system", "content": "You are a friendly driving companion helping the user stay alert during long drives. Keep responses SHORT (1-2 sentences). Ask engaging questions, share fun facts, or tell jokes. Be warm and conversational."]
                ]
            ],
            "firstMessage": "Hey! I'm here to keep you company on your drive. If you could road trip anywhere right now, where would you go?",
            "voice": [
                "provider": "11labs",
                "voiceId": "cgSgspJ2msm6clMCkdW9"  // Jessica from 11Labs
            ]
        ]
        do {
            try await vapi.start(assistant: assistant)
            print("Vapi call started successfully")
        } catch {
            print("Error starting call: \(error)")
            callState = .ended
            // Resume AR if call failed
            onCallDidEnd?()
        }
    }

    func endCall() {
        vapi.stop()
        print("Vapi call stopped")

        // Resume AR session (which will reconfigure its audio session)
        onCallDidEnd?()
    }

    func toggleMute() {
        isMuted.toggle()
        Task {
            try? await vapi.setMuted(isMuted)
        }
    }

    private func waitForARSessionPause() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            var hasResumed = false
            var observer: NSObjectProtocol?

            let resume = {
                guard !hasResumed else { return }
                hasResumed = true
                if let obs = observer {
                    NotificationCenter.default.removeObserver(obs)
                }
                continuation.resume()
            }

            observer = NotificationCenter.default.addObserver(
                forName: NSNotification.Name("ARSessionFullyPaused"),
                object: nil,
                queue: .main
            ) { _ in
                // Small additional buffer for iOS to fully release resources
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    resume()
                }
            }

            // Timeout after 3 seconds in case notification never comes
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                resume()
            }
        }
    }

    private func configureAudioForSpeaker() {
        // Small delay to ensure Daily's audio session is fully set up
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            do {
                let audioSession = AVAudioSession.sharedInstance()

                // Log current state
                print("Current audio category: \(audioSession.category.rawValue)")
                print("Current audio mode: \(audioSession.mode.rawValue)")
                print("Current route outputs: \(audioSession.currentRoute.outputs.map { $0.portType.rawValue })")
                print("Current route inputs: \(audioSession.currentRoute.inputs.map { $0.portType.rawValue })")

                // Force speaker output
                try audioSession.overrideOutputAudioPort(.speaker)
                print("Audio routed to speaker - new route: \(audioSession.currentRoute.outputs.map { $0.portType.rawValue })")
            } catch {
                print("Error routing audio to speaker: \(error)")
            }
        }
    }

    private func startCallTimer() {
        callStartTime = Date()
        callTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            DispatchQueue.main.async {
                guard let self = self, let start = self.callStartTime else { return }
                self.callDuration = Date().timeIntervalSince(start)
            }
        }
    }

    private func stopCallTimer() {
        callTimer?.invalidate()
        callTimer = nil
        callDuration = 0
        callStartTime = nil
    }

    var formattedDuration: String {
        let minutes = Int(callDuration) / 60
        let seconds = Int(callDuration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    var isCallActive: Bool { callState == .started }
    var isConnecting: Bool { callState == .loading }
}
