import 'package:freezed_annotation/freezed_annotation.dart';

part 'vending_print_job_ok_response.freezed.dart';
part 'vending_print_job_ok_response.g.dart';

@freezed
class VendingPrintJobOkResponse with _$VendingPrintJobOkResponse {
  const factory VendingPrintJobOkResponse({
    required bool ok,
    // 차감 반영 후 잔량. null은 머신 레코드를 찾지 못한 경우.
    int? cardCurrentCount,
    int? cardCapacity,
  }) = _VendingPrintJobOkResponse;

  factory VendingPrintJobOkResponse.fromJson(Map<String, dynamic> json) =>
      _$VendingPrintJobOkResponseFromJson(json);
}
