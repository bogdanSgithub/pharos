//
//  EmergencyContactSetupView.swift
//  mchacks
//
//  Redesigned emergency contact setup
//

import SwiftUI
import ContactsUI

struct EmergencyContactSetupView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var emergencyManager = EmergencyContactManager.shared

    var isFirstLaunch: Bool = false
    var onComplete: (() -> Void)?

    @State private var showContactPicker = false

    var body: some View {
        ZStack {
            AppColors.backgroundPrimary
                .ignoresSafeArea()

            VStack(spacing: 32) {
                Spacer()

                // Icon
                ZStack {
                    Circle()
                        .fill(AppColors.error.opacity(0.15))
                        .frame(width: 120, height: 120)

                    Circle()
                        .fill(AppColors.error.opacity(0.1))
                        .frame(width: 160, height: 160)

                    Image(systemName: "phone.fill")
                        .font(.system(size: 48))
                        .foregroundColor(AppColors.error)
                }

                // Title & Description
                VStack(spacing: 12) {
                    Text("Emergency Contact")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundColor(AppColors.textPrimary)

                    Text("Select someone to call if the app detects you may be falling asleep while driving.")
                        .font(.system(size: 16))
                        .foregroundColor(AppColors.textSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }

                // Current contact display
                if emergencyManager.hasEmergencyContact {
                    VStack(spacing: 8) {
                        HStack(spacing: 12) {
                            ZStack {
                                Circle()
                                    .fill(AppColors.success.opacity(0.15))
                                    .frame(width: 48, height: 48)

                                Image(systemName: "person.fill")
                                    .font(.system(size: 20))
                                    .foregroundColor(AppColors.success)
                            }

                            VStack(alignment: .leading, spacing: 4) {
                                Text(emergencyManager.emergencyContactName ?? "")
                                    .font(.system(size: 17, weight: .semibold))
                                    .foregroundColor(AppColors.textPrimary)

                                Text(emergencyManager.emergencyPhoneNumber ?? "")
                                    .font(.system(size: 14))
                                    .foregroundColor(AppColors.textSecondary)
                            }

                            Spacer()

                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 24))
                                .foregroundColor(AppColors.success)
                        }
                        .padding(16)
                        .background(AppColors.backgroundCard)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .overlay(
                            RoundedRectangle(cornerRadius: 16)
                                .stroke(AppColors.success.opacity(0.3), lineWidth: 1)
                        )
                    }
                    .padding(.horizontal, 24)
                }

                Spacer()

                // Buttons
                VStack(spacing: 12) {
                    Button(action: { showContactPicker = true }) {
                        HStack(spacing: 8) {
                            Image(systemName: emergencyManager.hasEmergencyContact ? "arrow.triangle.2.circlepath" : "person.crop.circle.badge.plus")
                                .font(.system(size: 18))
                            Text(emergencyManager.hasEmergencyContact ? "Change Contact" : "Select Contact")
                                .font(.system(size: 17, weight: .semibold))
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(AppColors.error)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                    }

                    if emergencyManager.hasEmergencyContact {
                        Button(action: {
                            onComplete?()
                            dismiss()
                        }) {
                            Text("Continue")
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 16)
                                .background(AppColors.accent)
                                .clipShape(RoundedRectangle(cornerRadius: 14))
                        }
                    }

                    if !isFirstLaunch {
                        Button("Cancel") {
                            dismiss()
                        }
                        .foregroundColor(AppColors.textTertiary)
                        .padding(.top, 8)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 40)
            }
        }
        .sheet(isPresented: $showContactPicker) {
            ContactPickerView { name, phone in
                emergencyManager.saveEmergencyContact(name: name, phoneNumber: phone)
            }
        }
    }
}

// MARK: - Contact Picker
struct ContactPickerView: UIViewControllerRepresentable {
    var onContactSelected: (String, String) -> Void

    func makeUIViewController(context: Context) -> CNContactPickerViewController {
        let picker = CNContactPickerViewController()
        picker.delegate = context.coordinator
        picker.predicateForEnablingContact = NSPredicate(format: "phoneNumbers.@count > 0")
        return picker
    }

    func updateUIViewController(_ uiViewController: CNContactPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onContactSelected: onContactSelected)
    }

    class Coordinator: NSObject, CNContactPickerDelegate {
        var onContactSelected: (String, String) -> Void

        init(onContactSelected: @escaping (String, String) -> Void) {
            self.onContactSelected = onContactSelected
        }

        func contactPicker(_ picker: CNContactPickerViewController, didSelect contact: CNContact) {
            let name = "\(contact.givenName) \(contact.familyName)".trimmingCharacters(in: .whitespaces)
            if let phoneNumber = contact.phoneNumbers.first?.value.stringValue {
                onContactSelected(name, phoneNumber)
            }
        }
    }
}

#Preview {
    EmergencyContactSetupView(isFirstLaunch: true)
}
