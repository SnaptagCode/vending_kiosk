import 'package:freezed_annotation/freezed_annotation.dart';

part 'vending_print_job_ok_response.freezed.dart';
part 'vending_print_job_ok_response.g.dart';

@freezed
class VendingPrintJobOkResponse with _$VendingPrintJobOkResponse {
  const factory VendingPrintJobOkResponse({
    required bool ok,
  }) = _VendingPrintJobOkResponse;

  factory VendingPrintJobOkResponse.fromJson(Map<String, dynamic> json) =>
      _$VendingPrintJobOkResponseFromJson(json);
}
