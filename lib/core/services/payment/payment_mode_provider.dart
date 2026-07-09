import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:vending_kiosk/core/common/constants/alert_key.dart';
import 'package:vending_kiosk/core/common/logger/logger_service.dart';
import 'package:vending_kiosk/core/common/logger/slack_log_service.dart';
import 'package:vending_kiosk/presentation/kiosk_shell/kiosk_info_service.dart';

part 'payment_mode_provider.g.dart';

/// 결제 모드 전환 주체 (server는 P2 원격 제어에서 사용 예정)
enum PaymentModeSource {
  localAdmin('로컬 관리자'),
  server('서버');

  final String label;
  const PaymentModeSource(this.label);
}

/// 결제 On/Off(무료 모드) 상태.
/// true = 결제 ON(유료), false = 결제 OFF(무료 모드).
/// 파일이 없거나 손상된 경우 결제 ON이 안전 기본값.
@Riverpod(keepAlive: true)
class PaymentModeNotifier extends _$PaymentModeNotifier {
  static const _fileName = 'payment_mode.json';

  @override
  bool build() => _loadFromDisk();

  static String? _filePath() {
    final home = Platform.environment['USERPROFILE'];
    if (home == null) return null;
    return p.join(home, 'Snaptag', 'runtime', _fileName);
  }

  bool _loadFromDisk() {
    try {
      final path = _filePath();
      if (path == null) return true;
      final file = File(path);
      if (!file.existsSync()) return true;
      final data = json.decode(file.readAsStringSync());
      return (data['isPaymentEnabled'] as bool?) ?? true;
    } catch (e) {
      logger.e('payment_mode.json 로드 실패 — 기본값 ON 사용', error: e);
      return true;
    }
  }

  Future<void> setEnabled(bool value, {required PaymentModeSource source}) async {
    if (state == value) return; // 전환 시에만 저장·알림 → 전환당 1회 보장
    await _persist(value, source);
    state = value;
    _notifySlack(value, source);
  }

  Future<void> _persist(bool value, PaymentModeSource source) async {
    final path = _filePath();
    if (path == null) return;
    final dir = Directory(p.dirname(path));
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
    }

    final content = json.encode({
      'isPaymentEnabled': value,
      'updatedAt': DateTime.now().toIso8601String(),
      'source': source.name,
    });
    // 원자적 쓰기: 임시 파일 작성 후 rename으로 교체 (쓰기 도중 종료 시 기존 파일 보존)
    final tmp = File('$path.tmp');
    await tmp.writeAsString(content, flush: true);
    await tmp.rename(path);
  }

  void _notifySlack(bool value, PaymentModeSource source) {
    final key = value ? InfoKey.paymentModeOn.key : InfoKey.paymentModeOff.key;
    SlackLogService().sendBroadcastLogToSlack(key);
    // 서버 알림 정의 미등록 시 브로드캐스트가 드랍되므로 일반 로그 병행 발송
    final machineId = ref.read(kioskInfoServiceProvider)?.kioskMachineId.toString() ?? 'unknown';
    SlackLogService().sendLogToSlack(
      '*[MachineId: $machineId]*\n결제 모드 전환: ${value ? 'OFF→ON (유료 결제)' : 'ON→OFF (무료 모드)'} (제어: ${source.label})',
    );
  }
}
