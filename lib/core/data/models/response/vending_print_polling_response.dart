import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:vending_kiosk/core/data/models/enums/vending_print_job_type.dart';

part 'vending_print_polling_response.freezed.dart';
part 'vending_print_polling_response.g.dart';

@freezed
class VendingPrintPollingResponse with _$VendingPrintPollingResponse {
  const factory VendingPrintPollingResponse({
    required bool exists,
    required int? printJobId,
    required int? kioskMachineId,
    required VendingPrintJobType? type,
    required int? kioskOrderId,
    required int? requestCount,
    required List<int>? printedPhotoCardIdList,
    required int? reprintTargetCount,
  }) = _VendingPrintPollingResponse;

  factory VendingPrintPollingResponse.fromJson(Map<String, dynamic> json) =>
      _$VendingPrintPollingResponseFromJson(json);
}
