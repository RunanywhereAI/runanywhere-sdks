// SPDX-License-Identifier: Apache-2.0
//
// `CuaActionKind` is deliberately hand-mirrored rather than re-exported from
// `lib/generated/cua.pbenum.dart`, so the public capability surface stays
// proto-free — the same choice Swift, Kotlin, React Native, and Web make for
// their own CUA kind enums. That choice is only safe while something ties the
// mirror back to the IDL, which is what this test is: `dart_bridge_cua.dart`
// maps `proto.type.value` straight through `CuaActionKind.fromValue`, so a
// value that drifts silently re-labels every action crossing the bridge.

import 'package:flutter_test/flutter_test.dart';
import 'package:runanywhere/generated/cua.pbenum.dart' as pb;
import 'package:runanywhere/public/capabilities/runanywhere_cua.dart';

void main() {
  group('CuaActionKind mirrors runanywhere.v1.CuaActionType', () {
    // Pairing is explicit because the two naming conventions differ
    // (`CUA_ACTION_TYPE_UNSPECIFIED` is the public `unknown`).
    const mirrored = <int, CuaActionKind>{
      0: CuaActionKind.unknown,
      1: CuaActionKind.leftClick,
      2: CuaActionKind.rightClick,
      3: CuaActionKind.doubleClick,
      4: CuaActionKind.tripleClick,
      5: CuaActionKind.mouseMove,
      6: CuaActionKind.leftClickDrag,
      7: CuaActionKind.type,
      8: CuaActionKind.key,
      9: CuaActionKind.scroll,
      10: CuaActionKind.hscroll,
      11: CuaActionKind.visitUrl,
      12: CuaActionKind.historyBack,
      13: CuaActionKind.webSearch,
      14: CuaActionKind.readPageAnswer,
      15: CuaActionKind.pauseMemorize,
      16: CuaActionKind.askUser,
      17: CuaActionKind.wait,
      18: CuaActionKind.terminate,
    };

    test('every generated proto value maps to a distinct kind', () {
      for (final proto in pb.CuaActionType.values) {
        final kind = mirrored[proto.value];
        expect(
          kind,
          isNotNull,
          reason: 'cua.proto gained ${proto.name} — mirror it in CuaActionKind',
        );
        expect(
          kind!.value,
          proto.value,
          reason: 'wire value drift between $kind and ${proto.name}',
        );
        // The exact call dart_bridge_cua.dart makes on every parse.
        expect(CuaActionKind.fromValue(proto.value), kind);
      }
    });

    test('no kind exists without a generated proto counterpart', () {
      final protoValues = pb.CuaActionType.values.map((v) => v.value).toSet();
      for (final kind in CuaActionKind.values) {
        expect(
          protoValues.contains(kind.value),
          isTrue,
          reason: '$kind has no CuaActionType — it can never be decoded',
        );
      }
    });

    test('an out-of-range wire value degrades to unknown', () {
      expect(CuaActionKind.fromValue(9999), CuaActionKind.unknown);
      expect(CuaActionKind.fromValue(-1), CuaActionKind.unknown);
    });
  });
}
