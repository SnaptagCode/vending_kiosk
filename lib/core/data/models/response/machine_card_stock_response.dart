import 'package:freezed_annotation/freezed_annotation.dart';

part 'machine_card_stock_response.freezed.dart';
part 'machine_card_stock_response.g.dart';

@freezed
class MachineCardStockResponse with _$MachineCardStockResponse {
  const factory MachineCardStockResponse({
    required int id,
    required String name,
    required int cardCurrentCount,
    required int cardCapacity,
  }) = _MachineCardStockResponse;

  factory MachineCardStockResponse.fromJson(Map<String, dynamic> json) =>
      _$MachineCardStockResponseFromJson(json);
}
