//
//  InitializationViews.swift
//  RunAnywhereAI
//

import SwiftUI

// MARK: - Loading view shown while the SDK bootstraps

struct InitializationLoadingView: View {
    @State private var isAnimating = false
    private let startDate = Date()

    var body: some View {
        VStack(spacing: 32) {
            Spacer()

            Image("runanywhere_logo")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 120, height: 120)
                .scaleEffect(isAnimating ? 1.05 : 1.0)
                .animation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true), value: isAnimating)

            VStack(spacing: 12) {
                Text("Setting Up Your AI")
                    .font(.title2)
                    .fontWeight(.semibold)

                Text("Preparing your private AI assistant...")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            // TimelineView drives the progress bar — SwiftUI cancels it
            // automatically when this view leaves the hierarchy, which avoids
            // the never-cancelled Timer leak of the previous implementation.
            TimelineView(.periodic(from: startDate, by: 0.02)) { ctx in
                let elapsed = ctx.date.timeIntervalSince(startDate)
                let progress = elapsed.truncatingRemainder(dividingBy: 2.0) / 2.0
                VStack(spacing: 8) {
                    ProgressView(value: progress, total: 1.0)
                        .progressViewStyle(.linear)
                        .tint(AppColors.primaryAccent)
                        .frame(width: 240)

                    Text("Initializing SDK...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        #if os(iOS)
        .background(Color(.systemBackground))
        #else
        .background(Color(NSColor.windowBackgroundColor))
        #endif
        .onAppear {
            isAnimating = true
        }
    }
}

// MARK: - Error view shown when SDK initialisation fails

struct InitializationErrorView: View {
    let error: Error
    let retryAction: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 60))
                .foregroundColor(.orange)

            Text("Initialization Failed")
                .font(.title2)
                .fontWeight(.semibold)

            Text(error.localizedDescription)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            Button("Retry") {
                retryAction()
            }
            .buttonStyle(.borderedProminent)
            .tint(AppColors.primaryAccent)
            .font(.headline)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        #if os(iOS)
        .background(Color(.systemBackground))
        #else
        .background(Color(NSColor.windowBackgroundColor))
        #endif
    }
}
