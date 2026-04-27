import 'package:flutter_test/flutter_test.dart';
import 'package:runanywhere/native/platform_loader.dart';

void main() {
  test('windows loader search paths include executable, cwd, and bare dll', () {
    expect(
      PlatformLoader.windowsLibrarySearchPathsForTesting(
        'rac_commons',
        resolvedExecutablePath: r'C:\dart-sdk\bin\dart.exe',
      ),
      <String>[
        r'C:\dart-sdk\bin\rac_commons.dll',
        r'.\rac_commons.dll',
        'rac_commons.dll',
      ],
    );
  });
}
