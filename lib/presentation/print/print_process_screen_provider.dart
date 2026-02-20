import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:vending_kiosk/core/common/logger/logger_service.dart';
import 'package:vending_kiosk/core/data/models/request/card_stock_consume_request.dart';
import 'package:vending_kiosk/core/data/repositories/kiosk_repository.dart';
import 'package:vending_kiosk/core/services/card_dispenser_service.dart';
import 'package:vending_kiosk/presentation/home/print_quantity_provider.dart';
import 'package:vending_kiosk/presentation/kiosk_shell/kiosk_info_service.dart';
import 'package:vending_kiosk/presentation/print/dispense_progress_provider.dart';
import 'package:vending_kiosk/presentation/setup/uuid_provider.dart';

part 'print_process_screen_provider.g.dart';

@Riverpod(keepAlive: true)
class PrintProcessScreenProvider extends _$PrintProcessScreenProvider {
  @override
  FutureOr<void> build() => null;

  /// 프린트(카드 배출) 작업 시작 — ViewModel 진입점
  Future<void> startPrint() async {
    state = const AsyncLoading();
    try {
      await _handlePrintProcess();
      state = const AsyncData(null);
    } catch (e, st) {
      logger.e('PrintProcessScreenProvider.print failure', error: e, stackTrace: st);
      // 프린터 에러 시 모터 정지(Disable) → 초기화(Reset) 후 연결 해제
      final notifier = ref.read(cardDispenserServiceProvider.notifier);
      try {
        await notifier.resetDispenser();
      } catch (resetErr) {
        logger.w('PrintProcessScreenProvider: dispenser reset on print error failed', error: resetErr);
      }
      state = AsyncError(e, st);
    }
  }

  Future<void> disconnectCardDispenser() async {
    await ref.read(cardDispenserServiceProvider.notifier).disconnect();
  }

  Future<void> _handlePrintProcess() async {
    await _executePrint();
  }

  Future<void> _executePrint() async {
    final quantity = ref.read(printQuantityProvider);

    ref.read(dispenseProgressNotifierProvider.notifier).initialize(quantity);

    logger.i('Print process: Dispensing $quantity pre-printed card(s) one by one...');

    for (int i = 0; i < quantity; i++) {
      logger.i('Print process: Dispensing card ${i + 1}/$quantity...');

      await ref.read(cardDispenserServiceProvider.notifier).dispenseAndWait(count: 1);

      ref.read(kioskRepositoryProvider).consumeCardStock(
            CardStockConsumeRequest(
              machineId: ref.read(kioskInfoServiceProvider)!.kioskMachineId,
              uniqueKey: await ref.read(deviceUuidProvider.future),
              requestCount: 1,
            ),
          );

      ref.read(dispenseProgressNotifierProvider.notifier).increment();

      // 다음 배출 전에 장치가 standby로 바뀔 때까지 폴링 (가능한 한 짧은 대기)
      await Future.delayed(const Duration(seconds: 1));
      logger.i('Print process: Card ${i + 1}/$quantity dispensed successfully');
    }

    // await ref.read(cardDispenserServiceProvider.notifier).dispenseAndWait(count: quantity);

    logger.i('Print process: All $quantity card(s) dispensed successfully');
  }
}
