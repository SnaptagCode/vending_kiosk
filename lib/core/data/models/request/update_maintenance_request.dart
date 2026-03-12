import 'package:freezed_annotation/freezed_annotation.dart';

part 'update_maintenance_request.freezed.dart';
part 'update_maintenance_request.g.dart';

@freezed
class UpdateMaintenanceRequest with _$UpdateMaintenanceRequest {
  const factory UpdateMaintenanceRequest({
    required bool isUnderMaintenance,
  }) = _UpdateMaintenanceRequest;

  factory UpdateMaintenanceRequest.fromJson(Map<String, dynamic> json) =>
      _$UpdateMaintenanceRequestFromJson(json);
}
