import 'package:flutter/material.dart';
import 'package:runanywhere_ai/core/services/permission_service.dart';

abstract class VisionPermissionGateway {
  Future<bool> requestCameraPermission(BuildContext context);
}

class AppVisionPermissionGateway implements VisionPermissionGateway {
  @override
  Future<bool> requestCameraPermission(BuildContext context) {
    return PermissionService.shared.requestCameraPermission(context);
  }
}
