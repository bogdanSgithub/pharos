//
//  CompanionButton.swift
//  mchacks
//

import SwiftUI

struct CompanionButton: View {
    @Binding var isActive: Bool
    @State private var isAnimating = false

    var body: some View {
        Button(action: { isActive = true }) {
            ZStack {
                // Outer glow when animating
                if isAnimating {
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [.purple.opacity(0.4), .clear],
                                center: .center,
                                startRadius: 25,
                                endRadius: 50
                            )
                        )
                        .frame(width: 80, height: 80)
                        .scaleEffect(isAnimating ? 1.2 : 1.0)
                }

                // Main button
                ZStack {
                    // Gradient background
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color(red: 0.4, green: 0.3, blue: 0.9),
                                    Color(red: 0.6, green: 0.2, blue: 0.8)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 60, height: 60)
                        .shadow(color: .purple.opacity(0.5), radius: 8, y: 4)

                    // Icon
                    Image(systemName: "waveform.circle.fill")
                        .font(.system(size: 28, weight: .medium))
                        .foregroundColor(.white)
                        .symbolEffect(.pulse, options: .repeating, isActive: isAnimating)
                }
            }
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 2).repeatForever(autoreverses: true)) {
                isAnimating = true
            }
        }
    }
}

#Preview {
    ZStack {
        Color.black.ignoresSafeArea()
        CompanionButton(isActive: .constant(false))
    }
}
