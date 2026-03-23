import 'package:vending_kiosk/core/common/logger/logger_service.dart';
import 'package:vending_kiosk/core/common/logger/slack_log_service.dart';
import 'package:vending_kiosk/core/services/card_dispenser_manager.dart';
import 'package:vending_kiosk/core/services/card_dispenser_service.dart';
import 'package:vending_kiosk/presentation/kiosk_shell/kiosk_info_service.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'card_dispenser_connect_state.g.dart';

enum CardDispenserConnectState {
  connected,
  disconnected,
  setupInComplete,
  pending,
  checking, // 연결 확인 중
}

@Riverpod(keepAlive: true)
class CardDispenserConnect extends _$CardDispenserConnect {
  bool _isChecking = false;

  @override
  CardDispenserConnectState build() {
    // keepAlive이므로 앱 생애주기 동안 build()는 1회만 실행됨 → 체크도 1회
    Future.microtask(_runCheck);
    return CardDispenserConnectState.pending;
  }

  /// UI 재시도 버튼에서 호출
  Future<void> runCheck() => _runCheck();

  Future<void> _runCheck() async {
    if (_isChecking) return;
    _isChecking = true;
    state = CardDispenserConnectState.checking;

    try {
      if (CardDispenserManager.isInstanceConnected) {
        final isHealthy = await CardDispenserManager.checkInstanceHealth();
        if (isHealthy) {
          _applyState(CardDispenserConnectState.connected);
          return;
        }
        await CardDispenserManager.disconnectAll();
      }

      final detected = await ref.read(cardDispenserServiceProvider.notifier).autoDetectPort();

      _applyState(detected != null ? CardDispenserConnectState.connected : CardDispenserConnectState.disconnected);
    } catch (e) {
      logger.e('CardDispenserConnect: check failed', error: e);
      _applyState(CardDispenserConnectState.disconnected);
    } finally {
      _isChecking = false;
    }
  }

  void _applyState(CardDispenserConnectState newState) {
    state = newState;
    final machineId = ref.read(kioskInfoServiceProvider)?.kioskMachineId ?? 0;
    try {
      SlackLogService().sendLogToSlack('*[MachineId: $machineId]*\nCard Dispenser ${newState.name}');
    } catch (_) {}
  }

  /// 외부(카드 배출 테스트 화면 등)에서 상태 직접 갱신 시 사용
  void update(CardDispenserConnectState newState) {
    if (newState == CardDispenserConnectState.pending || newState == CardDispenserConnectState.checking) return;
    _applyState(newState);
  }
}
