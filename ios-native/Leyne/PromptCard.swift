//  PromptCard.swift
//
//  The on-brand sheet shown for both soft prompts (review / coffee). It is a
//  pure presentation layer — all pacing + action logic lives in PromptCenter.
//  For the review, "Rate Leyne" triggers Apple's native StoreKit sheet (via
//  PromptCenter.confirmReview); we never fake the rating UI here.

import SwiftUI

struct PromptCard: View {
    let prompt: AppPrompt

    @EnvironmentObject private var m: AppModel
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

    private var iconName: String {
        prompt == .rateApp ? "star.fill" : "cup.and.saucer.fill"
    }
    private var iconTint: Color {
        prompt == .rateApp
            ? Color(red: 1.0, green: 0.72, blue: 0.13)     // amber star
            : Color(red: 0.76, green: 0.50, blue: 0.27)    // warm coffee
    }
    private var title: String {
        prompt == .rateApp ? "Enjoying Leyne?" : "Support Leyne"
    }
    private var message: String {
        switch prompt {
        case .rateApp:
            return "A quick App Store rating helps other Singapore commuters find Leyne. It only takes a moment."
        case .buyCoffee:
            return "Leyne is free and ad-light. If it's saved you a wait, you can buy me a coffee — totally optional."
        }
    }
    private var primaryTitle: String {
        prompt == .rateApp ? "Rate Leyne" : "Buy me a coffee"
    }
    private var secondaryTitle: String {
        prompt == .rateApp ? "Not now" : "Maybe later"
    }

    // MARK: - Actions

    private func primary() {
        fb.success()
        switch prompt {
        case .rateApp:   PromptCenter.shared.confirmReview { openURL($0) }
        case .buyCoffee: PromptCenter.shared.confirmCoffee { openURL($0) }
        }
    }

    private func secondary() {
        fb.select()
        switch prompt {
        case .rateApp:   PromptCenter.shared.declineReview()
        case .buyCoffee: PromptCenter.shared.declineCoffee()
        }
    }
}
