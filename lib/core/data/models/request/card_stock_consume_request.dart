import 'package:freezed_annotation/freezed_annotation.dart';

part 'card_stock_consume_request.freezed.dart';
part 'card_stock_consume_request.g.dart';

@freezed
class CardStockConsumeRequest with _$CardStockConsumeRequest {
  const factory CardStockConsumeRequest({
    required int machineId,
    required String uniqueKey,
    required int requestCount,
  }) = _CardStockConsumeRequest;

  factory CardStockConsumeRequest.fromJson(Map<String, dynamic> json) =>
      _$CardStockConsumeRequestFromJson(json);
}
