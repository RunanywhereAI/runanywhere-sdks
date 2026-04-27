import 'package:flutter_test/flutter_test.dart';
import 'package:runanywhere/infrastructure/download/download_service.dart';

void main() {
  test(
      'multi-file download progress uses cumulative bytes over total model size',
      () {
    expect(
      calculateOverallMultiFileDownloadProgressForTesting(
        cumulativeDownloadedBytes: 150,
        downloadedBytesForCurrentFile: 50,
        totalModelBytes: 400,
      ),
      closeTo(0.5, 0.0001),
    );
  });

  test(
      'multi-file download progress clamps to completion when bytes exceed total',
      () {
    expect(
      calculateOverallMultiFileDownloadProgressForTesting(
        cumulativeDownloadedBytes: 380,
        downloadedBytesForCurrentFile: 40,
        totalModelBytes: 400,
      ),
      closeTo(1.0, 0.0001),
    );
  });

  test(
      'multi-file download progress uses zero when total model size is unknown',
      () {
    expect(
      calculateOverallMultiFileDownloadProgressForTesting(
        cumulativeDownloadedBytes: 150,
        downloadedBytesForCurrentFile: 50,
        totalModelBytes: 0,
      ),
      0,
    );
  });

  test('estimates per-file size from total model size when needed', () {
    expect(
      estimatePerFileDownloadSizeForTesting(
        totalModelBytes: 300,
        totalFiles: 3,
      ),
      100,
    );
    expect(
      estimatePerFileDownloadSizeForTesting(
        totalModelBytes: null,
        totalFiles: 3,
      ),
      0,
    );
  });
}
