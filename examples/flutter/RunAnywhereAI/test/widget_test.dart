// Basic Flutter widget test for RunAnywhereAI app.

import 'package:flutter_test/flutter_test.dart';

import 'package:runanywhere_ai/app/runanywhere_ai_app.dart';

void main() {
  testWidgets('App launches smoke test', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(const RunAnywhereAIApp());

    // Verify that the app renders without errors.
    // The app should show the main navigation view.
    await tester.pumpAndSettle();

    // Basic check that something rendered
    expect(find.byType(RunAnywhereAIApp), findsOneWidget);
  });
}
