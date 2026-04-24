// SPDX-License-Identifier: Apache-2.0
//
// parity_test.dart (flutter_test shim) — T7.3.
//
// Forwards to the shared parity_test harness under
// `tests/streaming/parity_test.dart` so
// `flutter test test/parity_test.dart` works without setting
// RAC_PARITY_GOLDEN manually. The shared harness resolves the golden
// fixture relative to its own source path (or via CWD walk), so this
// shim only needs to re-export its `main()`.

import '../../../../../tests/streaming/parity_test.dart' as parity;

void main() => parity.main();
