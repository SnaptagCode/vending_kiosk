import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:vending_kiosk/core/data/models/enums/enums.dart';

part 'update_vending_order_status_request.freezed.dart';
part 'update_vending_order_status_request.g.dart';

@freezed
class UpdateVendingOrderStatusRequest with _$UpdateVendingOrderStatusRequest {
  const factory UpdateVendingOrderStatusRequest({
    required int kioskMachineId,
    required int kioskEventId,
    required OrderStatus status,
    required int amount,
    String? authSeqNumber,
    String? approvalNumber,
    String? tradeNumber,
    String? uniqueNumber,
    String? description,
    String? detail,
  }) = _UpdateVendingOrderStatusRequest;

  factory UpdateVendingOrderStatusRequest.fromJson(Map<String, dynamic> json) =>
      _$UpdateVendingOrderStatusRequestFromJson(json);
}
