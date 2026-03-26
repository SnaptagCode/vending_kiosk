import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:vending_kiosk/core/common/logger/logger_service.dart';
import 'package:vending_kiosk/core/common/logger/slack_log_service.dart';
import 'package:vending_kiosk/core/data/models/enums/printed_status.dart';
import 'package:vending_kiosk/core/data/models/request/card_stock_consume_request.dart';
import 'package:vending_kiosk/core/data/models/request/update_vending_print_status_request.dart';
import 'package:vending_kiosk/core/data/repositories/kiosk_repository.dart';
import 'package:vending_kiosk/core/services/card_dispenser_manager.dart';
import 'package:vending_kiosk/core/services/card_dispenser_service.dart';
import 'package:vending_kiosk/presentation/home/payment/create_order_info_state.dart';
import 'package:vending_kiosk/presentation/home/payment/payment_failed_type.dart';
import 'package:vending_kiosk/presentation/home/print_quantity_provider.dart';
import 'package:vending_kiosk/presentation/kiosk_shell/kiosk_info_service.dart';
import 'package:vending_kiosk/presentation/setup/uuid_provider.dart';

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
        // ARBITRARY: 배출기 동작만
        await _executeDispenserOnlyJob();
        await ref.read(kioskRepositoryProvider).succeedVendingPrintJob(printJobId);
        await ref.read(kioskRepositoryProvider).consumeCardStock(
              CardStockConsumeRequest(
                machineId: ref.read(kioskInfoServiceProvider)!.kioskMachineId,
                uniqueKey: await ref.read(deviceUuidProvider.future),
                requestCount: 1,
              ),
            );
      } else {
        await _executePrintJob();
      }
      state = const AsyncData(null);
    } catch (e, st) {
      logger.e('PrintProcessScreenProvider.print failure', error: e, stackTrace: st);

      state = AsyncError(e, st);

      if (printJobId != null) {
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
    try {
      ref.read(kioskRepositoryProvider).updateVendingPrintStatus(
            printedPhotoCardId,
            UpdateVendingPrintStatusRequest(status: status),
          );
    } catch (e) {
      rethrow;
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
      SlackLogService().sendCardDispenserErrorLogToSlack(e.toString());
      rethrow;
    }

    try {
      logger.i('=====================================================');
      logger.i('3. Print process consumeCardStock');
      logger.i('=====================================================');

      await ref.read(kioskRepositoryProvider).consumeCardStock(
            CardStockConsumeRequest(
              machineId: ref.read(kioskInfoServiceProvider)!.kioskMachineId,
              uniqueKey: await ref.read(deviceUuidProvider.future),
              requestCount: 1,
            ),
          );
    } catch (e) {
      SlackLogService().sendErrorLogToSlack('PrintService._executePrint consumeCardStock failure: $e');
    }

    logger.i('=====================================================');
    logger.i('4. Print process increment');
    logger.i('=====================================================');

    ref.read(printQuantityNotifierProvider.notifier).increment();

    logger.i('=====================================================');
    logger.i('5. Print process waitUntilStandby');
    logger.i('=====================================================');
    // 다음 배출 전에 장치가 standby로 바뀔 때까지 폴링 (가능한 한 짧은 대기)
    // await Future.delayed(const Duration(seconds: 1));
    logger.i('Print process: Card $printedPhotoCardId dispensed successfully');
  }
}
