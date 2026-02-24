import 'package:freezed_annotation/freezed_annotation.dart';

part 'vending_reprint_response.freezed.dart';
part 'vending_reprint_response.g.dart';

@freezed
class VendingReprintResponse with _$VendingReprintResponse {
  factory VendingReprintResponse({
    required int orderId,
    required int totalCount,
    required int completedCount,
    required int reprintableCount,
    required List<int> reprintableIds,
  }) = _VendingReprintResponse;

  factory VendingReprintResponse.fromJson(Map<String, dynamic> json) =>
      _$VendingReprintResponseFromJson(json);
}
