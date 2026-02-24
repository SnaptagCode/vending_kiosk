import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:vending_kiosk/core/data/models/entities/paging_entity.dart';
import 'package:vending_kiosk/core/data/models/entities/vending_print_item_entity.dart';

part 'vending_print_list_response.freezed.dart';
part 'vending_print_list_response.g.dart';

@freezed
class VendingPrintListResponse with _$VendingPrintListResponse {
  factory VendingPrintListResponse({
    required List<VendingPrintItemEntity> list,
    required PagingEntity paging,
  }) = _VendingPrintListResponse;

  factory VendingPrintListResponse.fromJson(Map<String, dynamic> json) =>
      _$VendingPrintListResponseFromJson(json);
}
