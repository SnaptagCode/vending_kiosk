import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:vending_kiosk/core/data/models/enums/enums.dart';

part 'vending_order_entity.freezed.dart';
part 'vending_order_entity.g.dart';

@freezed
class VendingOrderEntity with _$VendingOrderEntity {
  factory VendingOrderEntity({
    required int id,
    required int kioskEventId,
    required int kioskMachineId,
    required DateTime created,
    required DateTime modified,
    required bool isDeleted,
    String? photoAuthNumber,
    required int amount,
    String? purchaseAuthNumber,
    required OrderStatus status,
    String? tradeNumber,
    String? uniqueNumber,
    required PaymentType paymentType,
    int? latestKioskPaymentRecordId,
    required bool isTest,
    String? description,
    int? backPhotoCardId,
    required bool isSingleSided,
  }) = _VendingOrderEntity;

  factory VendingOrderEntity.fromJson(Map<String, dynamic> json) => _$VendingOrderEntityFromJson(json);
}
