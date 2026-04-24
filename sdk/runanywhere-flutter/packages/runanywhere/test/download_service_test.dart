import 'package:flutter_test/flutter_test.dart';
import 'package:runanywhere/infrastructure/download/download_service.dart';

void main() {
  test('multi-file download progress reaches the current file boundary', () {
    expect(
      calculateOverallMultiFileDownloadProgressForTesting(
        completedFiles: 2,
        totalFiles: 3,
        downloadedBytesForCurrentFile: 100,
        totalBytesForCurrentFile: 100,
      ),
      closeTo(1.0, 0.0001),
    );
  });

  test('multi-file download progress uses zero when file size is unknown', () {
    expect(
      calculateOverallMultiFileDownloadProgressForTesting(
        completedFiles: 1,
        totalFiles: 3,
        downloadedBytesForCurrentFile: 50,
        totalBytesForCurrentFile: 0,
      ),
      closeTo(1 / 3, 0.0001),
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
