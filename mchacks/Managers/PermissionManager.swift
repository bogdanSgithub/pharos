//
//  PermissionManager.swift
//  mchacks
//

import Foundation
import AVFoundation
import CoreLocation
import Combine
import UIKit

@MainActor
class PermissionManager: ObservableObject {
    // Published properties for permission status
    @Published var cameraStatus: AVAuthorizationStatus = .notDetermined
    @Published var microphoneStatus: AVAuthorizationStatus = .notDetermined
    @Published var locationStatus: CLAuthorizationStatus = .notDetermined
    
    // Computed properties for easy checking
    var isCameraAuthorized: Bool {
        cameraStatus == .authorized
    }
    
    var isMicrophoneAuthorized: Bool {
        microphoneStatus == .authorized
    }
    
    var isLocationAuthorized: Bool {
        locationStatus == .authorizedWhenInUse || locationStatus == .authorizedAlways
    }
    
    var allRequiredPermissionsGranted: Bool {
        isCameraAuthorized && isLocationAuthorized
    }
    
    init() {
        // Check current status on init
        checkAllPermissions()
    }
    
    // MARK: - Check Permissions
    
    func checkAllPermissions() {
        cameraStatus = AVCaptureDevice.authorizationStatus(for: .video)
        microphoneStatus = AVCaptureDevice.authorizationStatus(for: .audio)
        locationStatus = CLLocationManager().authorizationStatus
    }
    
    // MARK: - Request Camera Permission
    
    func requestCameraPermission() async -> Bool {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        
        switch status {
        case .authorized:
            await MainActor.run {
                cameraStatus = .authorized
            }
            return true
            
        case .notDetermined:
            let granted = await AVCaptureDevice.requestAccess(for: .video)
            await MainActor.run {
                cameraStatus = AVCaptureDevice.authorizationStatus(for: .video)
            }
            return granted
            
        case .denied, .restricted:
            await MainActor.run {
                cameraStatus = status
            }
            return false
            
        @unknown default:
            return false
        }
    }
    
    // MARK: - Request Microphone Permission
    
    func requestMicrophonePermission() async -> Bool {
        let status = AVCaptureDevice.authorizationStatus(for: .audio)
        
        switch status {
        case .authorized:
            await MainActor.run {
                microphoneStatus = .authorized
            }
            return true
            
        case .notDetermined:
            let granted = await AVCaptureDevice.requestAccess(for: .audio)
            await MainActor.run {
                microphoneStatus = AVCaptureDevice.authorizationStatus(for: .audio)
            }
            return granted
            
        case .denied, .restricted:
            await MainActor.run {
                microphoneStatus = status
            }
            return false
            
        @unknown default:
            return false
        }
    }
    
    // MARK: - Request Location Permission (delegates to LocationManager)
    
    func requestLocationPermission(using locationManager: LocationManager) {
        locationManager.requestPermission()
        // LocationManager will update its own status, which we can observe
    }
    
    // MARK: - Open Settings
    
    func openSettings() {
        if let settingsUrl = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(settingsUrl)
        }
    }
    
    // MARK: - Request All Required Permissions
    
    func requestAllRequiredPermissions() async {
        _ = await requestCameraPermission()
        // Location is handled separately via LocationManager
    }
}
