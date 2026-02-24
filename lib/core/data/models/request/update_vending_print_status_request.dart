import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:vending_kiosk/core/data/models/enums/enums.dart';

part 'update_vending_print_status_request.freezed.dart';
part 'update_vending_print_status_request.g.dart';

@freezed
class UpdateVendingPrintStatusRequest with _$UpdateVendingPrintStatusRequest {
  const factory UpdateVendingPrintStatusRequest({
    required PrintedStatus status,
  }) = _UpdateVendingPrintStatusRequest;

  factory UpdateVendingPrintStatusRequest.fromJson(Map<String, dynamic> json) =>
      _$UpdateVendingPrintStatusRequestFromJson(json);
}
