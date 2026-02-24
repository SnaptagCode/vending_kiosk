import 'package:freezed_annotation/freezed_annotation.dart';

part 'vending_order_status_response.freezed.dart';
part 'vending_order_status_response.g.dart';

@freezed
abstract class VendingOrderStatusResponse with _$VendingOrderStatusResponse {
  const factory VendingOrderStatusResponse({
    required VendingOrderDto order,
    @Default([]) List<int> printedPhotoCardIds,
  }) = _VendingOrderStatusResponse;

  factory VendingOrderStatusResponse.fromJson(Map<String, dynamic> json) => _$VendingOrderStatusResponseFromJson(json);
}

@freezed
abstract class VendingOrderDto with _$VendingOrderDto {
  const factory VendingOrderDto({
    @Default(0) int id,
    @Default(0) int kioskEventId,
    @Default(0) int kioskMachineId,
    @Default('') String created,
    @Default('') String modified,
    @Default(false) bool isDeleted,
    @Default('') String photoAuthNumber,
    @Default(0) int amount,
    @Default('') String purchaseAuthNumber,
    @Default('') String status,
    @Default(null) String? tradeNumber,
    @Default(null) String? uniqueNumber,
    @Default('') String paymentType,
    @Default(0) int latestKioskPaymentRecordId,
    @Default(false) bool isTest,
    @Default(null) String? description,
    @Default(null) int? backPhotoCardId,
    @Default(false) bool isSingleSided,
  }) = _VendingOrderDto;

  factory VendingOrderDto.fromJson(Map<String, dynamic> json) => _$VendingOrderDtoFromJson(json);
}
