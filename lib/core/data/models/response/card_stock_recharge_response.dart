import 'package:freezed_annotation/freezed_annotation.dart';

part 'card_stock_recharge_response.freezed.dart';
part 'card_stock_recharge_response.g.dart';

@freezed
class CardStockRechargeResponse with _$CardStockRechargeResponse {
  const factory CardStockRechargeResponse({
    required int id,
    required String name,
    required int cardCurrentCount,
    required int cardCapacity,
    required bool slackNotified,
  }) = _CardStockRechargeResponse;

  factory CardStockRechargeResponse.fromJson(Map<String, dynamic> json) =>
      _$CardStockRechargeResponseFromJson(json);
}
