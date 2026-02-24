import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:vending_kiosk/core/data/models/entities/vending_order_entity.dart';

part 'create_vending_order_response.freezed.dart';
part 'create_vending_order_response.g.dart';

@freezed
class CreateVendingOrderResponse with _$CreateVendingOrderResponse {
  factory CreateVendingOrderResponse({
    required VendingOrderEntity order,
    required List<int> printedPhotoCardIds,
  }) = _CreateVendingOrderResponse;

  factory CreateVendingOrderResponse.fromJson(Map<String, dynamic> json) =>
      _$CreateVendingOrderResponseFromJson(json);
}
