import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runanywhere_ai/features/models/add_model_from_url_view.dart';
import 'package:runanywhere_ai/features/models/model_types.dart';
import 'package:runanywhere_ai/features/structured_output/structured_output_view.dart';

void main() {
  testWidgets('StructuredOutputView builds with example selector',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: StructuredOutputView(),
        ),
      ),
    );

    expect(find.byType(StructuredOutputView), findsOneWidget);
    expect(find.byType(DropdownButtonFormField<int>), findsOneWidget);
    expect(find.text('Recipe'), findsOneWidget);

    await tester.tap(find.byType(DropdownButtonFormField<int>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Weather').last);
    await tester.pumpAndSettle();

    final promptField = tester.widget<TextField>(find.byType(TextField));
    expect(promptField.controller?.text, 'What is the weather in Paris?');
  });

  testWidgets('AddModelFromURLView builds with framework selector',
      (tester) async {
    ModelInfo? addedModel;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AddModelFromURLView(
            onModelAdded: (model) => addedModel = model,
          ),
        ),
      ),
    );

    expect(find.byType(AddModelFromURLView), findsOneWidget);
    expect(find.text('Framework'), findsOneWidget);
    expect(find.text('Target Framework'), findsOneWidget);

    await tester.tap(find.byType(DropdownButtonFormField<LLMFramework>));
    await tester.pumpAndSettle();
    await tester.tap(find.text(LLMFramework.mediaPipe.displayName).last);
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextFormField).at(0), 'Test Model');
    await tester.enterText(
      find.byType(TextFormField).at(1),
      'https://example.com/model.gguf',
    );
    await tester.ensureVisible(find.text('Add Model'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add Model'));
    await tester.pump();

    expect(addedModel?.preferredFramework, LLMFramework.mediaPipe);
    expect(addedModel?.compatibleFrameworks, contains(LLMFramework.mediaPipe));
  });
}
