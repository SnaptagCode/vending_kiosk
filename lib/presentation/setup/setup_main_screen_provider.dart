import 'dart:io';

import 'package:vending_kiosk/core/common/launcher/launcher_service.dart';
import 'package:vending_kiosk/core/common/logger/logger_service.dart';
import 'package:vending_kiosk/core/common/logger/slack_log_service.dart';
import 'package:vending_kiosk/core/data/datasources/local/id_writer.dart';
import 'package:vending_kiosk/core/data/models/request/card_stock_recharge_request.dart';
import 'package:vending_kiosk/core/data/models/response/card_stock_recharge_response.dart';
import 'package:vending_kiosk/core/data/repositories/kiosk_repository.dart';
import 'package:vending_kiosk/core/data/repositories/payment_repository.dart';
import 'package:vending_kiosk/core/providers/version_notifier.dart';
import 'package:vending_kiosk/core/services/card_dispenser_manager.dart';
import 'package:vending_kiosk/core/services/card_dispenser_service.dart';
import 'package:vending_kiosk/presentation/core/card_count_provider.dart';
import 'package:vending_kiosk/presentation/kiosk_shell/kiosk_info_service.dart';
import 'package:vending_kiosk/presentation/setup/card_dispenser_connect_state.dart';
import 'package:vending_kiosk/presentation/setup/page_print_provider.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'setup_main_screen_provider.g.dart';

/// Setup Main Screen의 상태
class SetupMainState {
  final bool isLoading;
  final String? errorMessage;
  final CardDispenserConnectState cardDispenserState;
  final bool isCheckingDispenser;

  // UI 상태들
  final int machineId;
  final String currentVersion;
  final String latestVersion;
  final bool isUpdateAvailable;
  final int cardCurrentCount;
  final bool getInfoByKey;

  SetupMainState({
    this.isLoading = false,
    this.errorMessage,
    this.cardDispenserState = CardDispenserConnectState.disconnected,
    this.isCheckingDispenser = false,
    this.machineId = 0,
    this.currentVersion = '',
    this.latestVersion = '',
    this.isUpdateAvailable = false,
    this.cardCurrentCount = 0,
    this.getInfoByKey = true,
  });

  SetupMainState copyWith({
    bool? isLoading,
    String? errorMessage,
    CardDispenserConnectState? cardDispenserState,
    bool? isCheckingDispenser,
    int? machineId,
    String? currentVersion,
    String? latestVersion,
    bool? isUpdateAvailable,
    int? cardCurrentCount,
    bool? getInfoByKey,
  }) {
    return SetupMainState(
      isLoading: isLoading ?? this.isLoading,
      errorMessage: errorMessage,
      cardDispenserState: cardDispenserState ?? this.cardDispenserState,
      isCheckingDispenser: isCheckingDispenser ?? this.isCheckingDispenser,
      machineId: machineId ?? this.machineId,
      currentVersion: currentVersion ?? this.currentVersion,
      latestVersion: latestVersion ?? this.latestVersion,
      isUpdateAvailable: isUpdateAvailable ?? this.isUpdateAvailable,
      cardCurrentCount: cardCurrentCount ?? this.cardCurrentCount,
      getInfoByKey: getInfoByKey ?? this.getInfoByKey,
    );
  }
}

@riverpod
class SetupMainScreenNotifier extends _$SetupMainScreenNotifier {
  bool _isCheckingDispenser = false;
  bool _isDisposed = false;

  @override
  SetupMainState build() {
    logger.d('SetupMainScreenNotifier build');
    // 화면 진입 시 카드 배출기 연결 1회 시도
    Future.microtask(() => _checkCardDispenserConnection());

    ref.onDispose(() {
      _isDisposed = true;
    });

    // 다른 provider들을 listen해서 상태 동기화
    ref.listen(kioskInfoServiceProvider, (previous, next) {
      state = state.copyWith(machineId: next?.kioskMachineId ?? 0);
    });

    ref.listen<bool>(getInfoByKeyProvider, (previous, next) {
      state = state.copyWith(getInfoByKey: next);
    });

    ref.listen(versionStateProvider, (previous, next) {
      state = state.copyWith(
        currentVersion: next.currentVersion,
        latestVersion: next.latestVersion,
        isUpdateAvailable: next.currentVersion != next.latestVersion,
      );
    });

    ref.listen(cardCountProvider, (previous, next) {
      state = state.copyWith(
        cardCurrentCount: next.currentCount,
      );
    });

    // 초기값 설정
    final kioskInfo = ref.read(kioskInfoServiceProvider);
    final versionState = ref.read(versionStateProvider);
    final cardCountState = ref.read(cardCountProvider);

    return SetupMainState(
      machineId: kioskInfo?.kioskMachineId ?? 0,
      currentVersion: versionState.currentVersion,
      latestVersion: versionState.latestVersion,
      isUpdateAvailable: versionState.currentVersion != versionState.latestVersion,
      cardCurrentCount: cardCountState.currentCount,
      getInfoByKey: ref.read(getInfoByKeyProvider),
    );
  }

  /// 외부에서 재시도 호출용 (UI 버튼)
  Future<void> retryCardDispenserConnection() => _checkCardDispenserConnection();

  /// 카드 배출기 연결 상태 체크
  Future<void> _checkCardDispenserConnection() async {
    if (_isCheckingDispenser || _isDisposed) return;
    _isCheckingDispenser = true;
    state = state.copyWith(isCheckingDispenser: true);

    try {
      // 이미 연결되어 있으면 health check로 통신 가능 여부 확인
      if (CardDispenserManager.isInstanceConnected) {
        final isHealthy = await CardDispenserManager.checkInstanceHealth();
        if (_isDisposed) return;
        final connectState = isHealthy ? CardDispenserConnectState.connected : CardDispenserConnectState.disconnected;
        state = state.copyWith(cardDispenserState: connectState);
        ref.read(cardDispenserConnectProvider.notifier).update(connectState);
        return;
      }

      // 연결되지 않은 경우 기존 인스턴스 정리 후 자동 감지
      await CardDispenserManager.disconnectAll();

      if (_isDisposed) return;

      final service = ref.read(cardDispenserServiceProvider.notifier);
      final detected = await service.autoDetectPort();

      if (_isDisposed) return;

      if (detected == null) {
        state = state.copyWith(cardDispenserState: CardDispenserConnectState.disconnected);
        ref.read(cardDispenserConnectProvider.notifier).update(CardDispenserConnectState.disconnected);
        return;
      }

      final currentState = ref.read(cardDispenserServiceProvider);
      logger.d('SetupMainScreenNotifier currentState: $currentState');

      final connectState = currentState.when(
        idle: () => CardDispenserConnectState.disconnected,
        connecting: () => CardDispenserConnectState.setupInComplete,
        ready: () => CardDispenserConnectState.connected,
        dispensing: (_) => CardDispenserConnectState.disconnected,
        error: (_) => CardDispenserConnectState.disconnected,
      );

      state = state.copyWith(cardDispenserState: connectState);
      ref.read(cardDispenserConnectProvider.notifier).update(connectState);
    } catch (e) {
      logger.e('Failed to check card dispenser connection', error: e);
      if (_isDisposed) return;
      state = state.copyWith(cardDispenserState: CardDispenserConnectState.disconnected);
      ref.read(cardDispenserConnectProvider.notifier).update(CardDispenserConnectState.disconnected);
    } finally {
      _isCheckingDispenser = false;
      if (!_isDisposed) state = state.copyWith(isCheckingDispenser: false);
    }
  }

  /// 결제 디바이스 체크
  Future<bool> checkPaymentDevice() async {
    try {
      final response = await ref.read(paymentRepositoryProvider).check();
      SlackLogService().sendInspectionEndBroadcastLogToSlack(
        'inspection_end',
        isPaymentOn: true,
      );
      SlackLogService().sendLogToSlack("Payment Device check: $response");
      return true;
    } catch (e) {
      SlackLogService().sendInspectionEndBroadcastLogToSlack(
        'inspection_end',
        isPaymentOn: false,
      );
      SlackLogService().sendErrorLogToSlack("Payment Device check: $e");
      return false;
    }
  }

  /// Photocode 메타 정보 작성
  Future<void> writePhotocodeMeta() async {
    final kioskInfo = ref.read(kioskInfoServiceProvider);
    final cardCountState = ref.read(cardCountProvider);
    final versionState = ref.read(versionStateProvider);

    final machineId = kioskInfo?.kioskMachineId ?? 0;
    final eventId = kioskInfo?.kioskEventId ?? 0;
    final cardCountInfo = "${cardCountState.initialCount} / ${cardCountState.currentCount}";
    final currentVersion = versionState.currentVersion;

    final serviceNameMap = {
      "SUF": "수원FC",
      "SEF": "서울 이랜드 FC",
      "KEEFO": "성수 B'Day",
      "AGFC": "안산그리너스FC",
    };
    final eventType = kioskInfo?.eventType ?? '-';
    final serviceName = serviceNameMap[eventType] ?? '-';

    await writePhotocodeId(
      machineId.toString(),
      eventId.toString(),
      cardCountInfo.toString(),
      serviceName.toString(),
      currentVersion.toString(),
    );
  }

  /// 이벤트 실행 플로우 시작
  Future<void> startEventFlow() async {
    try {
      state = state.copyWith(isLoading: true);

      final kioskInfo = ref.read(kioskInfoServiceProvider);
      final cardCountState = ref.read(cardCountProvider);
      final versionState = ref.read(versionStateProvider);

      final machineId = kioskInfo?.kioskMachineId ?? 0;
      final kioskEventId = kioskInfo?.kioskEventId ?? 0;
      final currentVersion = versionState.currentVersion;
      final latestVersion = versionState.latestVersion;

      // End mark 삭제
      await ref.read(kioskRepositoryProvider).deleteEndMark(
            kioskEventId: kioskEventId,
            machineId: machineId,
            remainingSingleSidedCount: cardCountState.remainingSingleSidedCount,
          );

      SlackLogService().sendLogToSlack(
        'machineId:$machineId, currentVersion:$currentVersion, latestVersion:$latestVersion',
      );

      // PagePrintType 설정
      if (cardCountState.currentCount < 1) {
        ref.read(pagePrintProvider.notifier).set(PagePrintType.double);
        SlackLogService().sendLogToSlack(
          'machineId: $machineId, singleCard: $cardCountState, set pagePrintType double',
        );
      } else {
        ref.read(pagePrintProvider.notifier).set(PagePrintType.single);
        SlackLogService().sendLogToSlack(
          'machineId: $machineId, singleCard: $cardCountState, set pagePrintType single',
        );
      }

      state = state.copyWith(isLoading: false);
    } catch (e) {
      logger.e('Failed to start event flow', error: e);
      state = state.copyWith(
        isLoading: false,
        errorMessage: '이벤트 실행 중 오류가 발생했습니다.',
      );
      rethrow;
    }
  }

  /// 카드 재고 충전
  Future<CardStockRechargeResponse> rechargeCardStock({
    required int cardNumber,
  }) async {
    try {
      state = state.copyWith(isLoading: true);

      final response = await ref.read(kioskRepositoryProvider).rechargeCardStock(
            CardStockRechargeRequest(
              machineId: state.machineId,
              requestCount: cardNumber,
            ),
          );

      logger.d('rechargeCardStock response: $response');

      state = state.copyWith(isLoading: false);
      return response;
    } catch (e) {
      logger.e('Failed to recharge card stock', error: e);
      state = state.copyWith(
        isLoading: false,
        errorMessage: '카드 재고 충전 중 오류가 발생했습니다.',
      );
      rethrow;
    }
  }

  /// 앱 강제 업데이트 및 재시작
  Future<void> forceUpdateAndRestart() async {
    try {
      final launcherPath = await LauncherPathUtil.getLauncherPath();
      await ForceUpdateWriter.writeForceUpdateTrue();

      logger.d("Starting launcher for update");

      await Process.start(
        launcherPath,
        ['f'],
        runInShell: true,
        mode: ProcessStartMode.detached,
      );

      logger.d("Launcher started, exiting app");
      await CardDispenserManager.disconnectAll();
      exit(0);
    } catch (e) {
      logger.e('Failed to start launcher', error: e);
      state = state.copyWith(
        errorMessage: '업데이트 실행 중 오류가 발생했습니다.',
      );
      rethrow;
    }
  }

  /// 키오스크 앱 종료
  Future<void> exitKioskApp() async {
    try {
      final kioskInfo = ref.read(kioskInfoServiceProvider);
      final cardCountState = ref.read(cardCountProvider);

      await ref.read(kioskRepositoryProvider).endKioskApplication(
            kioskEventId: kioskInfo?.kioskEventId ?? 0,
            machineId: kioskInfo?.kioskMachineId ?? 0,
          );

      await CardDispenserManager.disconnectAll();
      exit(0);
    } catch (e) {
      logger.e('Failed to exit kiosk app', error: e);
      await CardDispenserManager.disconnectAll();
      exit(0);
    }
  }

  /// 에러 메시지 클리어
  void clearError() {
    state = state.copyWith(errorMessage: null);
  }
}
