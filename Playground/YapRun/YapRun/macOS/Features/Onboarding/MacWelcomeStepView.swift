#if os(macOS)
//
//  MacWelcomeStepView.swift
//  YapRun
//
//  macOS onboarding step 1: Animated logo reveal + tagline + Get Started.
//

import SwiftUI

struct MacWelcomeStepView: View {
    let viewModel: MacOnboardingViewModel

    @State private var logoVisible = false
    @State private var titleVisible = false
    @State private var taglineVisible = false
    @State private var buttonVisible = false

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            Image("yaprun_logo")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 100, height: 100)
                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                .scaleEffect(logoVisible ? 1.0 : 0.5)
                .opacity(logoVisible ? 1.0 : 0)
                .padding(.bottom, 24)

            Text("YapRun")
                .font(.system(size: 42, weight: .bold))
                .foregroundStyle(AppColors.textPrimary)
                .opacity(titleVisible ? 1.0 : 0)
                .offset(y: titleVisible ? 0 : 16)

            Text("Your voice. On device.")
                .font(.title3)
                .foregroundStyle(AppColors.textSecondary)
                .padding(.top, 8)
                .opacity(taglineVisible ? 1.0 : 0)
                .offset(y: taglineVisible ? 0 : 12)

            Spacer()

            Button {
                viewModel.advance()
            } label: {
                Text("Get Started")
                    .font(.headline)
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(AppColors.ctaOrange, in: Capsule())
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 60)
            .padding(.bottom, 40)
            .opacity(buttonVisible ? 1.0 : 0)
            .offset(y: buttonVisible ? 0 : 20)
        }
        .onAppear {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.7).delay(0.1)) {
                logoVisible = true
            }
            withAnimation(.easeOut(duration: 0.5).delay(0.4)) {
                titleVisible = true
            }
            withAnimation(.easeOut(duration: 0.5).delay(0.6)) {
                taglineVisible = true
            }
            withAnimation(.easeOut(duration: 0.5).delay(0.9)) {
                buttonVisible = true
            }
        }
    }
}

#endif
