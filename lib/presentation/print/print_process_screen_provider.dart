import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:vending_kiosk/core/common/logger/logger_service.dart';
import 'package:vending_kiosk/core/common/logger/slack_log_service.dart';
import 'package:vending_kiosk/core/data/models/enums/printed_status.dart';
import 'package:vending_kiosk/core/data/models/request/update_vending_print_status_request.dart';
import 'package:vending_kiosk/core/data/repositories/kiosk_repository.dart';
import 'package:vending_kiosk/core/services/card_dispenser_manager.dart';
import 'package:vending_kiosk/core/services/card_dispenser_service.dart';
import 'package:vending_kiosk/presentation/home/payment/create_order_info_state.dart';
import 'package:vending_kiosk/presentation/home/payment/payment_failed_type.dart';
import 'package:vending_kiosk/presentation/home/print_quantity_provider.dart';
import 'package:vending_kiosk/presentation/kiosk_shell/kiosk_info_service.dart';

part 'print_process_screen_provider.g.dart';

@Riverpod(keepAlive: true)
class PrintProcessScreenProvider extends _$PrintProcessScreenProvider {
  @override
  FutureOr<void> build() => null;

  /// 프린트(카드 배출) 작업 시작 — ViewModel 진입점
  Future<void> startPrint() async {
    state = const AsyncLoading();
    final printJobId = ref.read(printJobIdProvider);

    try {
      if (printJobId != null && ref.read(reprintIdsProvider) != null) {
        // REPRINT: 기존 출력 로직 그대로
        await _executePrintJob();
        await ref.read(kioskRepositoryProvider).succeedVendingPrintJob(printJobId);
      } else if (printJobId != null) {
        // ARBITRARY: 배출기 동작만 — 재고 차감은 서버가 job success 시점에 수행
        await _executeDispenserOnlyJob();
        await ref.read(kioskRepositoryProvider).succeedVendingPrintJob(printJobId);
      } else {
        await _executePrintJob();
      }
      state = const AsyncData(null);
    } catch (e, st) {
      logger.e('PrintProcessScreenProvider.print failure', error: e, stackTrace: st);

      state = AsyncError(e, st);

      // 요청 장수보다 적게 배출된 경우 브로드캐스트 알림
      final quantity = ref.read(printQuantityNotifierProvider);
      if (quantity.current < quantity.total) {
        SlackLogService().sendCardDispenseShortfallLogToSlack(
          requestedCount: quantity.total,
          dispensedCount: quantity.current,
          reason: e.toString(),
        );
      }

      if (printJobId != null) {
        if (ref.read(reprintIdsProvider) == null) {
          SlackLogService().sendArbitraryPrintFailLogToSlack();
        }
        await ref
            .read(kioskRepositoryProvider)
            .failVendingPrintJob(printJobId: printJobId, failureReason: e.toString());
      }
    }
  }

  /// polling ARBITRARY job 전용 — 배출기 동작만 수행
  Future<void> _executeDispenserOnlyJob() async {
    final quantity = ref.read(printQuantityNotifierProvider);
    for (int i = 0; i < quantity.total; i++) {
      logger.i('Print job: Dispensing card ${i + 1}/${quantity.total}...');
      SlackLogService().sendLogToSlack('Print job: Dispensing card ${i + 1}/${quantity.total}...');

      final dispenserReady = await CardDispenserManager.checkAndRecover();
      if (dispenserReady == false) {
        throw InsufficientCardStockException(description: '배출기에 카드가 없습니다.');
      }

      await ref.read(cardDispenserServiceProvider.notifier).dispenseAndWait(count: 1, index: i);
      ref.read(printQuantityNotifierProvider.notifier).increment();
    }
  }

  Future<void> disconnectCardDispenser() async {
    await ref.read(cardDispenserServiceProvider.notifier).disconnect();
  }

  Future<void> _executePrintJob() async {
    final quantity = ref.read(printQuantityNotifierProvider);
    final reprintIds = ref.read(reprintIdsProvider);
    final printedPhotoCardIds = reprintIds ?? ref.read(createOrderInfoProvider)?.printedPhotoCardIds ?? [];

    if (printedPhotoCardIds.length != quantity.total) {
      throw Exception('Printed photo card ids length is not equal to quantity total');
    }

    int printedPhotoCardId = 0;
    try {
      for (int i = 0; i < quantity.total; i++) {
        printedPhotoCardId = printedPhotoCardIds[i];
        logger.i('Print process: Dispensing card ${i + 1}/$quantity...');

        SlackLogService().sendLogToSlack(
            'Print process: Dispensing card ${i + 1}/$quantity... printedPhotoCardId: $printedPhotoCardId');

        // 프린트 상태 시작
        await _updatePrintStatus(printedPhotoCardId, PrintedStatus.started);

        // 실제 프린트 실행
        await _executePrint(printedPhotoCardId, i);

        // 프린트 상태 완료
        await _updatePrintStatus(printedPhotoCardId, PrintedStatus.completed);
      }
    } catch (e, stack) {
      logger.e('PrintService._executePrintJob failure', error: e, stackTrace: stack);
      SlackLogService().sendLogToSlack('PrintService._executePrintJob failure: $e');
      SlackLogService().sendErrorLogToSlack('PrintService._executePrintJob failure: $e');
      await _updatePrintStatus(printedPhotoCardId, PrintedStatus.failed);
      rethrow;
    }
  }

  Future<void> _updatePrintStatus(int printedPhotoCardId, PrintedStatus status) async {
    const maxRetries = 3;
    int attempt = 0;

    while (attempt < maxRetries) {
      try {
        await ref.read(kioskRepositoryProvider).updateVendingPrintStatus(
              printedPhotoCardId,
              UpdateVendingPrintStatusRequest(status: status),
            );
        return;
      } catch (e) {
        attempt++;
        // logger.w('PrintService._updatePrintStatus attempt $attempt/$maxRetries failure', error: e);

        if (attempt >= maxRetries) {
          final kioskInfo = ref.read(kioskInfoServiceProvider);
          final machineId = kioskInfo?.kioskMachineId ?? 0;
          final machineName = kioskInfo?.kioskMachineName ?? '';
          SlackLogService().sendErrorLogToSlack(
              '[MACHINE_NAME: $machineName (MACHINE_ID: $machineId)] PrintService._updatePrintStatus failure after $maxRetries retries: $e');
          logger.e('PrintService._updatePrintStatus failure', error: e);
          rethrow;
        }
        await Future.delayed(const Duration(milliseconds: 300));
      }
    }
  }

  Future<void> _executePrint(int printedPhotoCardId, int index) async {
    try {
      logger.i('=====================================================');
      logger.i('1. Print process checkAndRecover');
      logger.i('=====================================================');
      final dispenserReady = await CardDispenserManager.checkAndRecover();
      if (dispenserReady == false) {
        throw InsufficientCardStockException(
          description: '배출기에 카드가 없습니다.',
        );
      }

      logger.i('=====================================================');
      logger.i('2. Print process dispenseAndWait');
      logger.i('=====================================================');
      await ref.read(cardDispenserServiceProvider.notifier).dispenseAndWait(count: 1, index: index);
    } catch (e) {
      // if ((e as DispenserException).message != '카드 배출기 초기화 실패. 장치 상태를 확인해 주세요.') {
      //   SlackLogService().sendCardDispenserErrorLogToSlack(e.toString());
      // }
      rethrow;
    }

    logger.i('=====================================================');
    logger.i('3. Print process increment');
    logger.i('=====================================================');

    ref.read(printQuantityNotifierProvider.notifier).increment();

    logger.i('=====================================================');
    logger.i('4. Print process waitUntilStandby');
    logger.i('=====================================================');
    // 다음 배출 전에 장치가 standby로 바뀔 때까지 폴링 (가능한 한 짧은 대기)
    // await Future.delayed(const Duration(seconds: 1));
    logger.i('Print process: Card $printedPhotoCardId dispensed successfully');
  }
}
