import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:vending_kiosk/core/common/logger/logger_service.dart';
import 'package:vending_kiosk/core/common/logger/slack_log_service.dart';
import 'package:vending_kiosk/core/data/models/enums/printed_status.dart';
import 'package:vending_kiosk/core/data/models/request/card_stock_consume_request.dart';
import 'package:vending_kiosk/core/data/models/request/update_vending_print_status_request.dart';
import 'package:vending_kiosk/core/data/repositories/kiosk_repository.dart';
import 'package:vending_kiosk/core/services/card_dispenser_service.dart';
import 'package:vending_kiosk/presentation/home/payment/create_order_info_state.dart';
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
    try {
      await _executePrintJob();
      state = const AsyncData(null);
    } catch (e, st) {
      logger.e('PrintProcessScreenProvider.print failure', error: e, stackTrace: st);
      state = AsyncError(e, st);
    }
  }

  Future<void> disconnectCardDispenser() async {
    await ref.read(cardDispenserServiceProvider.notifier).disconnect();
  }

  Future<void> _executePrintJob() async {
    final quantity = ref.read(printQuantityNotifierProvider);
    final reprintIds = ref.read(reprintIdsProvider);
    final printedPhotoCardIds = reprintIds ?? ref.read(createOrderInfoProvider)?.printedPhotoCardIds ?? [];

    SlackLogService().sendLogToSlack('Printed photo card ids length: ${printedPhotoCardIds.length}');
    SlackLogService().sendLogToSlack('Quantity total: ${quantity.total}');
    if (printedPhotoCardIds.length != quantity.total) {
      throw Exception('Printed photo card ids length is not equal to quantity total');
    }

    // 재출력 IDs는 사용 후 초기화
    if (reprintIds != null) {
      ref.read(reprintIdsProvider.notifier).state = null;
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
        await _executePrint(printedPhotoCardId);

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

  Future<void> _executePrint(int printedPhotoCardId) async {
    try {
      await ref.read(cardDispenserServiceProvider.notifier).dispenseAndWait(count: 1);
    } catch (e) {
      rethrow;
    }

    try {
      await ref.read(kioskRepositoryProvider).consumeCardStock(
            CardStockConsumeRequest(
              machineId: ref.read(kioskInfoServiceProvider)!.kioskMachineId,
              uniqueKey: await ref.read(deviceUuidProvider.future),
              requestCount: 1,
            ),
          );
    } catch (e) {
      rethrow;
    }

    ref.read(printQuantityNotifierProvider.notifier).increment();

    // 다음 배출 전에 장치가 standby로 바뀔 때까지 폴링 (가능한 한 짧은 대기)
    await Future.delayed(const Duration(seconds: 1));
    logger.i('Print process: Card $printedPhotoCardId dispensed successfully');
  }
}
