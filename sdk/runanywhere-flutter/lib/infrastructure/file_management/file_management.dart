/// FileManagement feature barrel export
/// Matches iOS FileManagement module structure
library file_management;

// Re-export storage models from core
export '../../core/models/storage/storage.dart';

export 'protocol/file_management_error.dart';
export 'protocol/file_management_service.dart';
export 'services/simplified_file_manager.dart';
