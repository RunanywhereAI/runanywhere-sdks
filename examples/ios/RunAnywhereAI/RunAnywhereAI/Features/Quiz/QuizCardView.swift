import SwiftUI

struct QuizCardView: View {
    let question: QuizQuestion
    let offset: CGSize
    let scale: CGFloat
    let opacity: Double

    var body: some View {
        VStack(spacing: 0) {
            // Question Number Badge
            HStack {
                Text("Question")
                    .font(AppTypography.caption)
                    .foregroundColor(AppColors.textSecondary)
                Spacer()
            }
            .padding(.horizontal, AppSpacing.large)
            .padding(.top, AppSpacing.large)

            // Question Content
            ScrollView {
                Text(question.question)
                    .font(AppTypography.title3Medium)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, AppSpacing.large)
                    .padding(.vertical, AppSpacing.xxLarge)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(maxHeight: .infinity)

            // Swipe Indicators
            HStack {
                HStack {
                    Image(systemName: "arrow.left")
                    Text("FALSE")
                        .fontWeight(.bold)
                }
                .foregroundColor(.red)

                Spacer()

                HStack {
                    Text("TRUE")
                        .fontWeight(.bold)
                    Image(systemName: "arrow.right")
                }
                .foregroundColor(.green)
            }
            .font(AppTypography.subheadline)
            .padding(AppSpacing.large)
            .background(AppColors.backgroundGrouped)
        }
        .background(AppColors.backgroundPrimary)
        .cornerRadius(AppSpacing.cornerRadiusModal)
        .shadow(color: AppColors.shadowDefault, radius: AppSpacing.medium, x: 0, y: AppSpacing.xSmall)
        .offset(offset)
        .scaleEffect(scale)
        .opacity(opacity)
    }
}

struct QuizCardOverlay: View {
    let direction: SwipeDirection
    let intensity: Double

    var body: some View {
        ZStack {
            if direction == .left {
                RoundedRectangle(cornerRadius: AppSpacing.cornerRadiusModal)
                    .fill(Color.red.opacity(intensity * 0.3))

                VStack {
                    Image(systemName: "xmark.circle.fill")
                        .font(AppTypography.system80)
                        .foregroundColor(.red)
                    Text("FALSE")
                        .font(AppTypography.largeTitleBold)
                        .foregroundColor(.red)
                }
                .opacity(intensity)
            } else if direction == .right {
                RoundedRectangle(cornerRadius: AppSpacing.cornerRadiusModal)
                    .fill(Color.green.opacity(intensity * 0.3))

                VStack {
                    Image(systemName: "checkmark.circle.fill")
                        .font(AppTypography.system80)
                        .foregroundColor(.green)
                    Text("TRUE")
                        .font(AppTypography.largeTitleBold)
                        .foregroundColor(.green)
                }
                .opacity(intensity)
            }
        }
    }
}
