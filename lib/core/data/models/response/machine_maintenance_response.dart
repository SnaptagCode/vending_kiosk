import 'package:freezed_annotation/freezed_annotation.dart';

part 'machine_maintenance_response.freezed.dart';
part 'machine_maintenance_response.g.dart';

@freezed
class MachineMaintenanceResponse with _$MachineMaintenanceResponse {
  const factory MachineMaintenanceResponse({
    required int machineId,
    required bool isUnderMaintenance,
    List<MachineLogItem>? machineLogPaths,
  }) = _MachineMaintenanceResponse;

  factory MachineMaintenanceResponse.fromJson(Map<String, dynamic> json) =>
      _$MachineMaintenanceResponseFromJson(json);
}

@freezed
class MachineLogItem with _$MachineLogItem {
  const factory MachineLogItem({
    required int id,
    required String path,
  }) = _MachineLogItem;

  factory MachineLogItem.fromJson(Map<String, dynamic> json) =>
      _$MachineLogItemFromJson(json);
}
