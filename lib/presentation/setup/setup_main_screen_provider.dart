import 'dart:io';

import 'package:dio/dio.dart';
import 'package:vending_kiosk/core/common/launcher/launcher_service.dart';
import 'package:vending_kiosk/core/common/logger/logger_service.dart';
import 'package:vending_kiosk/core/common/logger/slack_log_service.dart';
import 'package:vending_kiosk/core/data/datasources/local/id_writer.dart';
import 'package:vending_kiosk/core/data/models/request/card_stock_recharge_request.dart';
import 'package:vending_kiosk/core/data/models/response/card_stock_recharge_response.dart';
import 'package:vending_kiosk/core/data/repositories/kiosk_repository.dart';
import 'package:vending_kiosk/core/providers/version_notifier.dart';
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
  final int cardCapacity;
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
    this.cardCapacity = 0,
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
    int? cardCapacity,
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
      cardCapacity: cardCapacity ?? this.cardCapacity,
      getInfoByKey: getInfoByKey ?? this.getInfoByKey,
    );
  }
}

@riverpod
class SetupMainScreenNotifier extends _$SetupMainScreenNotifier {
  bool _isDisposed = false;
  bool _hasFetchedStock = false;

  @override
  SetupMainState build() {
    logger.d('SetupMainScreenNotifier build');

    ref.onDispose(() {
      _isDisposed = true;
    });

    final kioskInfo = ref.watch(kioskInfoServiceProvider);
    final versionState = ref.watch(versionStateProvider);
    final getInfoByKey = ref.watch(getInfoByKeyProvider);
    // keepAlive provider watch: 체크 완료 시 UI 자동 갱신
    final cardDispenserState = ref.watch(cardDispenserConnectProvider);

    // 카드 재고는 화면 진입 시 1회만 조회
    if (!_hasFetchedStock) {
      _hasFetchedStock = true;
      Future.microtask(() => _fetchCardStock());
    }

    return SetupMainState(
      // checking/pending 상태이면 로딩 표시
      isCheckingDispenser: cardDispenserState == CardDispenserConnectState.checking ||
          cardDispenserState == CardDispenserConnectState.pending,
      cardDispenserState: cardDispenserState,
      machineId: kioskInfo?.kioskMachineId ?? 0,
      currentVersion: versionState.currentVersion,
      latestVersion: versionState.latestVersion,
      isUpdateAvailable: versionState.currentVersion != versionState.latestVersion,
      cardCurrentCount: kioskInfo?.cardCurrentCount ?? 0,
      cardCapacity: kioskInfo?.cardCapacity ?? 0,
      getInfoByKey: getInfoByKey,
    );
  }

  /// 외부에서 재시도 호출용 (UI 버튼)
  Future<void> retryCardDispenserConnection() => ref.read(cardDispenserConnectProvider.notifier).runCheck();

  /// 서버에서 최신 카드 재고 조회
  Future<void> _fetchCardStock() async {
    if (_isDisposed) return;
    final kioskInfo = ref.read(kioskInfoServiceProvider);
    if (kioskInfo == null) return;
    try {
      final stockResponse = await ref.read(kioskRepositoryProvider).getMachineCardStock(kioskInfo.kioskMachineId);
      if (_isDisposed) return;
      state = state.copyWith(
        cardCurrentCount: stockResponse.cardCurrentCount,
        cardCapacity: stockResponse.cardCapacity,
      );
    } catch (e) {
      logger.e('Failed to fetch card stock', error: e);
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

      logger.d('rechargeCardStock request: machineId=${state.machineId}, requestCount=$cardNumber');

      final response = await ref.read(kioskRepositoryProvider).rechargeCardStock(
            CardStockRechargeRequest(
              machineId: state.machineId,
              requestCount: cardNumber,
            ),
          );

      logger.d('rechargeCardStock response: $response');

      state = state.copyWith(isLoading: false, cardCurrentCount: response.cardCurrentCount);
      return response;
    } catch (e) {
      if (e is DioException) {
        logger.e('Failed to recharge card stock | status: ${e.response?.statusCode} | body: ${e.response?.data}', error: e);
      } else {
        logger.e('Failed to recharge card stock', error: e);
      }
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
      terminateProcess();
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

      await ref.read(kioskRepositoryProvider).endKioskApplication(
            kioskEventId: kioskInfo?.kioskEventId ?? 0,
            machineId: kioskInfo?.kioskMachineId ?? 0,
          );
    } catch (e) {
      logger.e('Failed to exit kiosk app', error: e);
    }
  }

  /// 에러 메시지 클리어
  void clearError() {
    state = state.copyWith(errorMessage: null);
  }
}
