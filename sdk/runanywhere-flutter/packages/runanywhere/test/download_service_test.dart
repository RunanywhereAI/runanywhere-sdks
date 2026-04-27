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
        completedFiles: 1,
        totalFiles: 4,
        currentFileSizeEstimate: 100,
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
        completedFiles: 3,
        totalFiles: 4,
        currentFileSizeEstimate: 100,
      ),
      closeTo(1.0, 0.0001),
    );
  });

  test(
      'multi-file download progress falls back to file progress when total model size is unknown',
      () {
    expect(
      calculateOverallMultiFileDownloadProgressForTesting(
        cumulativeDownloadedBytes: 0,
        downloadedBytesForCurrentFile: 50,
        totalModelBytes: 0,
        completedFiles: 1,
        totalFiles: 2,
        currentFileSizeEstimate: 100,
      ),
      closeTo(0.75, 0.0001),
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
