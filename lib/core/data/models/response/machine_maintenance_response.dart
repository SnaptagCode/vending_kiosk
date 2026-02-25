import 'package:freezed_annotation/freezed_annotation.dart';

part 'machine_maintenance_response.freezed.dart';
part 'machine_maintenance_response.g.dart';

@freezed
class MachineMaintenanceResponse with _$MachineMaintenanceResponse {
  const factory MachineMaintenanceResponse({
    required int machineId,
    required bool isUnderMaintenance,
  }) = _MachineMaintenanceResponse;

  factory MachineMaintenanceResponse.fromJson(Map<String, dynamic> json) =>
      _$MachineMaintenanceResponseFromJson(json);
}
