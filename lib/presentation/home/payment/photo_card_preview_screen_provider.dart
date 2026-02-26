import 'package:vending_kiosk/core/data/repositories/payment_repository.dart';
import 'package:vending_kiosk/presentation/setup/page_print_provider.dart';
import 'package:vending_kiosk/presentation/core/card_count_provider.dart';
import 'package:vending_kiosk/presentation/home/payment_response_state.dart';
import 'package:vending_kiosk/core/common/logger/logger_service.dart';
import 'package:vending_kiosk/core/data/models/response/payment_response.dart';
import 'package:vending_kiosk/core/data/models/request/create_vending_order_request.dart';
import 'package:vending_kiosk/core/data/repositories/kiosk_repository.dart';
import 'package:vending_kiosk/presentation/home/print_quantity_provider.dart';
import 'package:vending_kiosk/presentation/kiosk_shell/kiosk_info_service.dart';
import 'package:vending_kiosk/presentation/home/payment/payment_failed_type.dart';
import 'package:vending_kiosk/presentation/home/payment/payment_service.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'photo_card_preview_screen_provider.g.dart';

@riverpod
class PhotoCardPreviewScreenProvider extends _$PhotoCardPreviewScreenProvider {
  @override
  AsyncValue<void> build() => const AsyncValue.data(null);

  Future<void> payment() async {
    // 이미 로딩 중이면 중복 요청 방지
    if (state.isLoading) {
      return;
    }

    state = const AsyncValue.loading();

    try {
      // Step 1: 카드 재고 확인
      final kioskInfo = ref.read(kioskInfoServiceProvider);
      final quantity = ref.read(printQuantityNotifierProvider);

      if (kioskInfo == null) {
        throw Exception('Kiosk info is null');
      }

      final kioskRepo = ref.read(kioskRepositoryProvider);

      // 현재 카드 재고 조회
      final stockResponse = await kioskRepo.getMachineCardStock(kioskInfo.kioskMachineId);

      // 재고 확인
      if (stockResponse.cardCurrentCount < quantity.total) {
        throw InsufficientCardStockException(
          requestedQuantity: quantity.total,
          availableStock: stockResponse.cardCurrentCount,
          description: '카드 재고가 부족하여 결제를 진행할 수 없습니다.',
        );
      }

      // Step 2: 재고가 충분하면 결제 진행 (processPayment 내부에서 approve 1회 호출)
      await ref.read(paymentServiceProvider.notifier).processPayment();

      state = const AsyncValue.data(null);
    } catch (e, stack) {
      // 재고 부족 예외는 환불 처리하지 않음
      if (e is InsufficientCardStockException) {
        state = AsyncValue.error(e, stack);
        return;
      }
      state = AsyncValue.error(e, stack);
    }
  }
}
