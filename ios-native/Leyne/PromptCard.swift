//  PromptCard.swift
//
//  The on-brand sheet shown for the soft App Store review prompt. It is a
//  pure presentation layer — all pacing + action logic lives in PromptCenter.
//  For the review, "Rate Leyne" triggers Apple's native StoreKit sheet (via
//  PromptCenter.confirmReview); we never fake the rating UI here.

import SwiftUI

struct PromptCard: View {
    let prompt: AppPrompt

    @Environment(AppModel.self) private var m: AppModel
    @EnvironmentObject private var fb: Feedback
    @Environment(\.openURL) private var openURL

    private var t: Theme { m.t }

    var body: some View {
        VStack(spacing: 0) {
            iconChip
                .padding(.top, 28)
                .padding(.bottom, 18)

            Text(title)
                .font(t.sans(22, weight: .bold))
                .foregroundStyle(t.fg)
                .multilineTextAlignment(.center)

            Text(message)
                .font(t.sans(15, weight: .regular))
                .foregroundStyle(t.dim)
                .multilineTextAlignment(.center)
                .lineSpacing(2)
                .padding(.top, 8)
                .padding(.horizontal, 28)

            Spacer(minLength: 20)

            VStack(spacing: 10) {
                Button(action: primary) {
                    Text(primaryTitle)
                        .font(t.sans(16, weight: .semibold))
                        .foregroundStyle(t.bg)   // contrasts with the accent fill in both schemes
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 15)
                        .background(t.accent, in: Capsule())
                }
                .buttonStyle(.plain)

                Button(action: secondary) {
                    Text(secondaryTitle)
                        .font(t.sans(15, weight: .medium))
                        .foregroundStyle(t.dim)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 14)
        }
        .frame(maxWidth: .infinity)
        .background(t.bg)
        .presentationDetents([.height(370)])
        .presentationCornerRadius(28)
        .presentationDragIndicator(.visible)
    }

    // MARK: - Icon

    private var iconChip: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(iconTint.opacity(0.16))
                .frame(width: 72, height: 72)
            Image(systemName: iconName)
                .font(.system(size: 32, weight: .semibold))
                .foregroundStyle(iconTint)
        }
    }

    // MARK: - Content per prompt

    private var iconName: String { "star.fill" }
    private var iconTint: Color {
        Color(red: 1.0, green: 0.72, blue: 0.13)     // amber star
    }
    private var title: String { "Enjoying SG Transit?" }
    private var message: String {
        "A quick App Store rating helps other Singapore commuters find SG Transit. It only takes a moment."
    }
    private var primaryTitle: String { "Rate SG Transit" }
    private var secondaryTitle: String { "Not now" }

    // MARK: - Actions

    private func primary() {
        fb.success()
        PromptCenter.shared.confirmReview { openURL($0) }
    }

    private func secondary() {
        fb.select()
        PromptCenter.shared.declineReview()
    }
}
