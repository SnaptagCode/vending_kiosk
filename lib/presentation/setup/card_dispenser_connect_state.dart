import 'package:vending_kiosk/presentation/kiosk_shell/kiosk_info_service.dart';
import 'package:vending_kiosk/core/common/logger/slack_log_service.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'card_dispenser_connect_state.g.dart';

enum CardDispenserConnectState {
  connected,
  disconnected,
  setupInComplete,
  pending,
}

@Riverpod(keepAlive: true)
class CardDispenserConnect extends _$CardDispenserConnect {
  @override
  CardDispenserConnectState build() {
    return CardDispenserConnectState.pending;
  }

  /// 카드 배출기 연결 상태 업데이트
  /// @param state 연결 상태
  void update(CardDispenserConnectState state) {
    final machineId = ref.read(kioskInfoServiceProvider)?.kioskMachineId ?? 0;

    if (this.state == state || state == CardDispenserConnectState.pending) {
      // 현재 상태와 동일하거나, 상태가 'pending'인 경우
      // 'pending' 상태는 연결 상태가 아직 결정되지 않은 경우이므로, 아무 작업도 하지 않음
      return;
    }

    SlackLogService().sendLogToSlack('*[MachineId: $machineId]*\nCard Dispenser ${state.name}');

    this.state = state;
  }
}
