// Basic Flutter widget test for RunAnywhereAI app.

import 'package:flutter_test/flutter_test.dart';

import 'package:runanywhere_ai/app/runanywhere_ai_app.dart';

void main() {
  testWidgets('App launches smoke test', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(const RunAnywhereAIApp());

    // Verify that the app renders without errors.
    // Avoid pumpAndSettle here because app startup may keep scheduling frames
    // (for example, animations/tickers), which can cause test timeouts.
    const pumpStep = Duration(milliseconds: 100);
    const maxAttempts = 20;
    for (var attempt = 0; attempt < maxAttempts; attempt++) {
      await tester.pump(pumpStep);
      if (find.byType(RunAnywhereAIApp).evaluate().isNotEmpty) {
        break;
      }
    }

    // Basic check that something rendered
    expect(find.byType(RunAnywhereAIApp), findsOneWidget);
  });
}
