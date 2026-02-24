import 'package:freezed_annotation/freezed_annotation.dart';

part 'vending_print_status_response.freezed.dart';
part 'vending_print_status_response.g.dart';

@freezed
abstract class VendingPrintStatusResponse with _$VendingPrintStatusResponse {
  const factory VendingPrintStatusResponse({
    @Default(false) bool ok,
  }) = _VendingPrintStatusResponse;

  factory VendingPrintStatusResponse.fromJson(Map<String, dynamic> json) => _$VendingPrintStatusResponseFromJson(json);
}
