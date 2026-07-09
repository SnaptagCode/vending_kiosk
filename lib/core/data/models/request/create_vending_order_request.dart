import 'package:freezed_annotation/freezed_annotation.dart';

part 'create_vending_order_request.freezed.dart';
part 'create_vending_order_request.g.dart';

@freezed
class CreateVendingOrderRequest with _$CreateVendingOrderRequest {
  const factory CreateVendingOrderRequest({
    required int kioskMachineId,
    required int kioskEventId,
    required int printCount,
    required int amount,
    required bool isSingleSided,
    @Default(false) bool isFreeOrder,
  }) = _CreateVendingOrderRequest;

  factory CreateVendingOrderRequest.fromJson(Map<String, dynamic> json) =>
      _$CreateVendingOrderRequestFromJson(json);
}
