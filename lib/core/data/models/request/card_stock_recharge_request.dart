import 'package:freezed_annotation/freezed_annotation.dart';

part 'card_stock_recharge_request.freezed.dart';
part 'card_stock_recharge_request.g.dart';

@freezed
class CardStockRechargeRequest with _$CardStockRechargeRequest {
  const factory CardStockRechargeRequest({
    required int machineId,
    @Default(null) String? uniqueKey,
    required int requestCount,
  }) = _CardStockRechargeRequest;

  factory CardStockRechargeRequest.fromJson(Map<String, dynamic> json) => _$CardStockRechargeRequestFromJson(json);
}
