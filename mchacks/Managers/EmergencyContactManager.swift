//
//  EmergencyContactManager.swift
//  mchacks
//
//  Created for Strike 3 Emergency Call feature
//

import Foundation
import UIKit
import Combine

class EmergencyContactManager: ObservableObject {
    static let shared = EmergencyContactManager()

    @Published var emergencyPhoneNumber: String?
    @Published var emergencyContactName: String?
    @Published var hasCalledEmergency = false

    private var emergencyCallObserver: NSObjectProtocol?

    private init() {
        loadStoredContact()
        setupObserver()
    }

    private func loadStoredContact() {
        emergencyPhoneNumber = UserDefaults.standard.string(forKey: "emergencyContactNumber")
        emergencyContactName = UserDefaults.standard.string(forKey: "emergencyContactName")
    }

    private func setupObserver() {
        emergencyCallObserver = NotificationCenter.default.addObserver(
            forName: NSNotification.Name("TriggerEmergencyCall"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.callEmergencyContact()
        }
    }

    deinit {
        if let observer = emergencyCallObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    // MARK: - Save Emergency Contact

    func saveEmergencyContact(name: String, phoneNumber: String) {
        let cleanedNumber = phoneNumber.replacingOccurrences(of: "[^0-9+]", with: "", options: .regularExpression)

        UserDefaults.standard.set(name, forKey: "emergencyContactName")
        UserDefaults.standard.set(cleanedNumber, forKey: "emergencyContactNumber")

        emergencyContactName = name
        emergencyPhoneNumber = cleanedNumber
    }

    // MARK: - Call Emergency Contact

    func callEmergencyContact() {
        // Prevent multiple calls
        guard !hasCalledEmergency else {
            print("Emergency contact already called")
            return
        }

        hasCalledEmergency = true

        // Check if we have a stored emergency contact
        guard let phoneNumber = emergencyPhoneNumber, !phoneNumber.isEmpty else {
            print("No emergency contact found - prompting user to set one")
            // Post notification to show emergency contact setup
            NotificationCenter.default.post(name: NSNotification.Name("ShowEmergencyContactSetup"), object: nil)
            hasCalledEmergency = false
            return
        }

        guard let url = URL(string: "tel://\(phoneNumber)") else {
            print("Invalid phone number format")
            hasCalledEmergency = false
            return
        }

        DispatchQueue.main.async {
            if UIApplication.shared.canOpenURL(url) {
                UIApplication.shared.open(url, options: [:]) { success in
                    if success {
                        print("Calling emergency contact: \(self.emergencyContactName ?? "Unknown") at \(phoneNumber)")
                    } else {
                        print("Failed to initiate call")
                        self.hasCalledEmergency = false
                    }
                }
            } else {
                print("Cannot make phone calls on this device")
                self.hasCalledEmergency = false
            }
        }
    }

    // MARK: - Reset State

    func resetEmergencyState() {
        hasCalledEmergency = false
    }

    // MARK: - Check if Contact is Set

    var hasEmergencyContact: Bool {
        guard let number = emergencyPhoneNumber else { return false }
        return !number.isEmpty
    }
}
