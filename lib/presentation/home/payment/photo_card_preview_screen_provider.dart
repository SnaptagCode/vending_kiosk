import 'package:vending_kiosk/core/common/logger/slack_log_service.dart';
import 'package:vending_kiosk/core/services/card_dispenser_manager.dart';
import 'package:vending_kiosk/core/services/payment/payment_gateway.dart';
import 'package:vending_kiosk/core/services/payment/payment_gateway_provider.dart';
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
          description: '카드 재고가 부족하여 결제를 진행할 수 없습니다.',
        );
      }

      // Step 1.5: 물리적 배출기 상태 사전 확인 (연결된 경우에만)
      // 오류 상태면 reset 후 재확인, 복구 불가 시 예외 throw
      final dispenserReady = await CardDispenserManager.checkAndRecover();
      if (dispenserReady == false) {
        throw InsufficientCardStockException(
          description: '배출기에 카드가 없습니다.',
        );
      }

      await _checkPaymentTerminal(kioskInfo.kioskMachineId);

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

  Future<void> _checkPaymentTerminal(int machineId) async {
    String reason;
    try {
      final response = await ref.read(paymentGatewayProvider).check();
      if (response.res != '1003') return;
      reason = '이전 거래 미완료 (RES=1003)';
    } on PaymentDisabledException {
      return;
    } catch (e) {
      reason = '응답 없음 ($e)';
    }
    SlackLogService().sendErrorLogToSlack('*[MachineId: $machineId]*\n결제 단말기 응답 없음 - 결제 전 확인 실패\n- 사유: $reason');
    throw TerminalNoResponseException(description: reason);
  }
}
