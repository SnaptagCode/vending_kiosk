import 'package:freezed_annotation/freezed_annotation.dart';

part 'vending_print_job_fail_response.freezed.dart';
part 'vending_print_job_fail_response.g.dart';

@freezed
class VendingPrintJobFailResponse with _$VendingPrintJobFailResponse {
  const factory VendingPrintJobFailResponse({
    required String failureReason,
    required bool ok,
  }) = _VendingPrintJobFailResponse;

  factory VendingPrintJobFailResponse.fromJson(Map<String, dynamic> json) =>
      _$VendingPrintJobFailResponseFromJson(json);
}
