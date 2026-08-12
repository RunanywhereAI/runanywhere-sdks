// Basic Flutter widget test for RunAnywhereAI app.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:runanywhere_ai/app/runanywhere_ai_app.dart';

void main() {
  testWidgets('App launches smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const RunAnywhereAIApp());
    await tester.pump(const Duration(milliseconds: 16));

    expect(find.byType(RunAnywhereAIApp), findsOneWidget);
    expect(find.byType(MaterialApp), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
