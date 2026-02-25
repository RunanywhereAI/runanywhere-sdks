//
//  WelcomeStepView.swift
//  YapRun
//
//  Onboarding step 1: Animated logo reveal + tagline + Get Started.
//

#if os(iOS)
import SwiftUI

struct WelcomeStepView: View {
    let viewModel: OnboardingViewModel

    @State private var logoVisible = false
    @State private var titleVisible = false
    @State private var taglineVisible = false
    @State private var buttonVisible = false

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            // Logo
            Image("yaprun_logo")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 100, height: 100)
                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                .scaleEffect(logoVisible ? 1.0 : 0.5)
                .opacity(logoVisible ? 1.0 : 0)
                .padding(.bottom, 24)

            // App name
            Text("YapRun")
                .font(.system(size: 42, weight: .bold))
                .foregroundStyle(AppColors.textPrimary)
                .opacity(titleVisible ? 1.0 : 0)
                .offset(y: titleVisible ? 0 : 16)

            // Tagline
            Text("Your voice. On device.")
                .font(.title3)
                .foregroundStyle(AppColors.textSecondary)
                .padding(.top, 8)
                .opacity(taglineVisible ? 1.0 : 0)
                .offset(y: taglineVisible ? 0 : 12)

            Spacer()

            // Get Started
            Button {
                viewModel.advance()
            } label: {
                Text("Get Started")
                    .font(.headline)
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(AppColors.ctaOrange, in: Capsule())
            }
            .padding(.horizontal, 40)
            .padding(.bottom, 60)
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
