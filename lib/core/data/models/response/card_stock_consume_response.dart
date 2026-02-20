import 'package:freezed_annotation/freezed_annotation.dart';

part 'card_stock_consume_response.freezed.dart';
part 'card_stock_consume_response.g.dart';

@freezed
class CardStockConsumeResponse with _$CardStockConsumeResponse {
  const factory CardStockConsumeResponse({
    required int id,
    required String name,
    required int cardCurrentCount,
    required int cardCapacity,
    required bool slackNotified,
  }) = _CardStockConsumeResponse;

  factory CardStockConsumeResponse.fromJson(Map<String, dynamic> json) =>
      _$CardStockConsumeResponseFromJson(json);
}
