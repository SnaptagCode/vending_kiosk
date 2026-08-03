import 'package:freezed_annotation/freezed_annotation.dart';

part 'vending_print_status_response.freezed.dart';
part 'vending_print_status_response.g.dart';

@freezed
abstract class VendingPrintStatusResponse with _$VendingPrintStatusResponse {
  const factory VendingPrintStatusResponse({
    @Default(false) bool ok,
    // COMPLETED 차감이 반영된 잔량 스냅샷. 재고 미관리 머신은 null.
    int? cardCurrentCount,
    int? cardCapacity,
  }) = _VendingPrintStatusResponse;

  factory VendingPrintStatusResponse.fromJson(Map<String, dynamic> json) => _$VendingPrintStatusResponseFromJson(json);
}
