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
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
            }
            .padding(.horizontal)
            .padding(.top)

            // Question Content
            ScrollView {
                Text(question.question)
                    .font(.title3)
                    .fontWeight(.medium)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                    .padding(.vertical, 40)
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
            .font(.subheadline)
            .padding()
            .background(Color(.systemGray6))
        }
        .background(Color(.systemBackground))
        .cornerRadius(20)
        .shadow(color: .black.opacity(0.1), radius: 10, x: 0, y: 5)
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
                RoundedRectangle(cornerRadius: 20)
                    .fill(Color.red.opacity(intensity * 0.3))

                VStack {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 80))
                        .foregroundColor(.red)
                    Text("FALSE")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                        .foregroundColor(.red)
                }
                .opacity(intensity)
            } else if direction == .right {
                RoundedRectangle(cornerRadius: 20)
                    .fill(Color.green.opacity(intensity * 0.3))

                VStack {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 80))
                        .foregroundColor(.green)
                    Text("TRUE")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                        .foregroundColor(.green)
                }
                .opacity(intensity)
            }
        }
    }
}
