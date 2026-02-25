import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:vending_kiosk/core/data/models/enums/order_status.dart';

part 'vending_print_item_entity.freezed.dart';
part 'vending_print_item_entity.g.dart';

@freezed
abstract class VendingPrintItemEntity with _$VendingPrintItemEntity {
  const factory VendingPrintItemEntity({
    @Default(0) int kioskOrderId,
    @Default(0) int kioskEventId,
    @Default(0) int kioskMachineId,
    @Default('') String orderCreated,
    @Default('') String eventName,
    @Default(0) int amount,
    required OrderStatus orderStatus,
    @Default('') String purchaseAuthNumber,
    String? completedAt,
    String? refundedAt,
    @Default(false) bool isRefunded,
    @Default(0) int totalCount,
    @Default(0) int completedCount,
    @Default(false) bool reprintable,
  }) = _VendingPrintItemEntity;

  factory VendingPrintItemEntity.fromJson(Map<String, dynamic> json) => _$VendingPrintItemEntityFromJson(json);
}
