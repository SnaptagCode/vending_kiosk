import 'dart:async';

import 'package:vending_kiosk/core/common/errors/dispenser_exception.dart';
import 'package:vending_kiosk/core/common/logger/logger_service.dart';
import 'package:vending_kiosk/core/data/datasources/local/withtech_card_dispenser_serial.dart';

/// Manager for WITH-TECH card dispenser operations (runs on main isolate for reliable COM port open on Windows).
class CardDispenserManager {
  static CardDispenserManager? _instance;

  WithTechCardDispenserSerial? _serial;
  String? _connectedPort;

  CardDispenserManager._();

  static Future<CardDispenserManager> getInstance() async {
    try {
      if (_instance != null) return _instance!;
      logger.i('CardDispenserManager: Initializing...');
      _instance = CardDispenserManager._();
      await _instance!._init();
      return _instance!;
    } catch (e) {
      logger.e('CardDispenserManager: Failed to initialize', error: e);
      rethrow;
    }
  }

  Future<void> _init() async {
    logger.i('CardDispenserManager: Initialization completed');
  }

  /// 앱 종료 전 호출: COM 포트를 닫고 인스턴스를 정리합니다.
  static Future<void> disconnectAll() async {
    if (_instance == null) return;
    try {
      if (_instance!._serial != null) {
        await _instance!._serial!.disconnect();
        _instance!._serial = null;
      }
      _instance!._connectedPort = null;
      logger.i('AUTODETECTPORT CardDispenserManager: Disconnected and cleared');
    } catch (e) {
      logger.w('AUTODETECTPORT CardDispenserManager: disconnectAll error', error: e);
    } finally {
      _instance = null;
    }
  }

  /// 실제 시리얼 연결 여부
  bool get isConnected => _serial != null && _serial!.isConnected;

  /// 인스턴스 생성 없이 현재 연결 여부만 확인
  static bool get isInstanceConnected => _instance?.isConnected ?? false;

  /// 현재 연결된 포트 이름
  static String? get connectedPortName => _instance?._connectedPort;

  /// 결제 전 상태 확인 및 자동 복구.
  ///
  /// 1. 상태 확인 → standby면 즉시 정상 반환
  /// 2. warning + EMPTY → 카드 없음 반환
  /// 3. 그 외 비정상 → reset(0x12) 후 최대 3초 대기하며 재확인
  ///
  /// 반환값:
  /// - null: 미연결 (체크 불가, 호출부에서 스킵)
  /// - true: 정상 (standby)
  /// - false: 카드 없음 (EMPTY)
  ///
  /// Throws [Exception]: reset 후에도 비정상 상태 (결제 차단 권장)
  static Future<bool?> checkAndRecover() async {
    if (_instance == null || !_instance!.isConnected) return null;
    try {
      String status = await _instance!.getStatus();
      logger.d('CardDispenserManager.checkAndRecover: initial status=$status');

      // 정상 대기 상태
      if (status == 'standby') return true;

      // 카드 없음 → 즉시 반환
      // warning → 최대 3번 재시도 후 EMPTY 여부 판단
      if (status == 'warning') {
        final err = await _instance!.getError();
        if (err.errorCode?.contains('EMPTY') == true) {
          logger.w('CardDispenserManager.checkAndRecover: EMPTY 감지 ${err.errorCode}');
          return false;
        }
      }

      throw DispenserException('카드 배출기 상태 복구 실패 (status: $status)');
    } catch (e) {
      logger.e('CardDispenserManager.checkAndRecover failed', error: e);
      rethrow;
    }
  }

  /// 기존 인스턴스로 health check
  static Future<bool> checkInstanceHealth() async {
    if (_instance == null || !_instance!.isConnected) return false;
    try {
      return await _instance!.healthCheck();
    } catch (e) {
      logger.w('CardDispenserManager.checkInstanceHealth failed', error: e);
      return false;
    }
  }

  /// Connect to WITH-TECH card dispenser (must run on main isolate for Windows COM port).
  Future<bool> connect(String port, {int baudRate = 9600}) async {
    try {
      if (_serial != null) {
        if (_connectedPort != port || !_serial!.isConnected) {
          logger.d('AUTODETECTPORT CardDispenserManager: Disconnecting previous serial connection...');
          await _serial!.disconnect();
          _serial = null;
          _connectedPort = null;
          await Future<void>.delayed(const Duration(milliseconds: 200));
        }
      }

      if (_serial == null || !_serial!.isConnected) {
        logger.d(
            'AUTODETECTPORT CardDispenserManager: Creating new WithTechCardDispenserSerial instance (baud: $baudRate)...');
        _serial = WithTechCardDispenserSerial(baudRate: baudRate);
        final connected = await _serial!.connect(port);

        if (connected) {
          _connectedPort = port;
          logger.i('AUTODETECTPORT CardDispenserManager: Connected to $port');
          return true;
        } else {
          final available = WithTechCardDispenserSerial.getAvailablePorts();
          logger.e('AUTODETECTPORT CardDispenser Manager: 연결 실패 - 요청된 포트: $port, 사용 가능한 포트: $available');
          _serial = null;
          throw DispenserException(
            '카드 배출기 연결 실패 ($port)\n\n'
            '해결 방법:\n'
            '1. COM 포트 번호 확인 (장치 관리자에서 확인)\n'
            '2. 다른 시리얼 터미널 프로그램 종료\n'
            '3. USB 케이블 재연결\n'
            '4. 프로그램을 관리자 권한으로 실행\n\n'
            '사용 가능한 포트: $available',
          );
        }
      }

      return true;
    } catch (e) {
      logger.e('AUTODETECTPORT CardDispenserManager: Connect failed', error: e);
      _serial = null;
      _connectedPort = null;
      rethrow;
    }
  }

  /// 사용 가능한 COM 포트 목록 반환
  static List<String> getAvailablePorts() => WithTechCardDispenserSerial.getAvailablePorts();

  /// Health check
  Future<bool> healthCheck() async {
    if (_serial == null || !_serial!.isConnected) {
      throw DispenserException('Not connected');
    }
    return _serial!.healthCheck();
  }

  /// 초기화(Reset) — 배출기를 초기 상태로 복귀. 에러 발생 시 호출 권장.
  Future<bool> reset() async {
    if (_serial == null || !_serial!.isConnected) {
      logger.d('CardDispenserManager: reset skipped (not connected)');
      return false;
    }
    try {
      final ok = await _serial!.reset();
      if (ok) {
        logger.i('CardDispenserManager: Dispenser reset OK');
      } else {
        logger.w('CardDispenserManager: Dispenser reset returned false');
      }
      return ok;
    } catch (e) {
      logger.w('CardDispenserManager: reset failed', error: e);
      return false;
    }
  }

  /// 동작 금지(Disable) — WITH-TECH에는 별도 disable 명령이 없으므로 reset으로 대체.
  Future<bool> disable() async {
    if (_serial == null || !_serial!.isConnected) {
      logger.d('CardDispenserManager: disable skipped (not connected)');
      return false;
    }
    try {
      logger.i('CardDispenserManager: disable → reset (WITH-TECH does not have separate disable command)');
      return await _serial!.reset();
    } catch (e) {
      logger.w('CardDispenserManager: disable(reset) failed', error: e);
      return false;
    }
  }

  /// 동작 금지 해제(Enable) — WITH-TECH에는 별도 enable 명령이 없으므로 reset으로 대체.
  Future<bool> enable() async {
    if (_serial == null || !_serial!.isConnected) {
      logger.d('CardDispenserManager: enable skipped (not connected)');
      return false;
    }
    try {
      logger.i('CardDispenserManager: enable → reset (WITH-TECH does not have separate enable command)');
      return await _serial!.reset();
    } catch (e) {
      logger.w('CardDispenserManager: enable(reset) failed', error: e);
      return false;
    }
  }

  /// Dispense cards
  Future<bool> dispense(int count, {Duration? timeout}) async {
    if (_serial == null || !_serial!.isConnected) {
      throw DispenserException('Not connected');
    }
    return _serial!.payout(
      count,
      totalTimeout: timeout ?? const Duration(seconds: 15),
    );
  }

  /// Get status as string (mapped from WithTechDispenserStatusKind)
  ///
  /// 반환값:
  /// - 'standby': 준비 완료
  /// - 'dispensing': 배출 중
  /// - 'completed': 배출 성공
  /// - 'error': 배출 실패 / 에러
  /// - 'warning': 경고 (Empty 등), 배출 중 계속 폴링
  /// - 'halted': Hold 상태
  /// - 'unknown': 알 수 없음
  Future<String> getStatus() async {
    if (_serial == null || !_serial!.isConnected) {
      throw DispenserException('Not connected');
    }

    final status = await _serial!.getStatus();
    return _mapStatusKind(status.kind);
  }

  /// 마지막 배출 수량 조회
  Future<int?> getLastPaidOutQuantity() async {
    if (_serial == null || !_serial!.isConnected) return null;
    return _serial!.getLastPaidOutQuantity();
  }

  String _mapStatusKind(WithTechDispenserStatusKind kind) {
    return switch (kind) {
      WithTechDispenserStatusKind.ready => 'standby',
      WithTechDispenserStatusKind.payoutWorking => 'dispensing',
      WithTechDispenserStatusKind.counting => 'dispensing',
      WithTechDispenserStatusKind.payoutSuccess => 'completed',
      WithTechDispenserStatusKind.payoutFail => 'error',
      WithTechDispenserStatusKind.warning => 'warning',
      WithTechDispenserStatusKind.halted => 'halted',
      WithTechDispenserStatusKind.error => 'error',
      WithTechDispenserStatusKind.unknown => 'unknown',
    };
  }

  /// Get error details — WITH-TECH은 별도 에러 코드 대신 상태 바이트로 에러를 표현
  Future<({String? description, String? errorCode})> getError() async {
    if (_serial == null || !_serial!.isConnected) {
      throw DispenserException('Not connected');
    }
    final status = await _serial!.getStatus();
    final sb = status.statusByte;

    final isJam = (sb & 0x80) != 0;
    final isEmpty = (sb & 0x10) != 0;

    if (isJam && isEmpty) {
      return (description: '카드 걸림 + 카드 부족', errorCode: 'JAM+EMPTY');
    } else if (isJam) {
      return (description: '카드 걸림 (JAM)', errorCode: 'JAM');
    } else if (isEmpty) {
      return (description: '카드 부족 (EMPTY)', errorCode: 'EMPTY');
    }

    if (status.kind == WithTechDispenserStatusKind.payoutFail) {
      return (description: '카드 배출 실패', errorCode: 'PAYOUT_FAIL');
    }
    if (status.kind == WithTechDispenserStatusKind.error) {
      return (description: '장치 오류', errorCode: 'ERROR');
    }
    if (status.kind == WithTechDispenserStatusKind.payoutWorking) {
      return (description: '배출 중', errorCode: 'PAYOUT_WORKING');
    }

    return (description: null, errorCode: null);
  }

  /// 배출 전 장치 상태를 확인하고, 에러/Hold/Warning 상태면 reset 후 ready 대기.
  Future<void> _ensureReadyBeforeDispense() async {
    final preStatus = await getStatus();
    if (preStatus == 'standby' || preStatus == 'dispensing') return;

    logger.w('CardDispenserManager: pre-dispense status=$preStatus → reset 시도');
    await reset();

    final resetDeadline = DateTime.now().add(const Duration(seconds: 3));
    while (DateTime.now().isBefore(resetDeadline)) {
      final s = await getStatus();
      logger.d('CardDispenserManager: post-reset status=$s');
      if (s == 'standby') return;
      await Future.delayed(const Duration(milliseconds: 200));
    }
    logger.w('CardDispenserManager: reset 후에도 standby 미도달 (계속 진행)');
  }

  /// Dispense and wait until completion.
  ///
  /// WITH-TECH 프로토콜은 TX 1회 후 장치가 RX를 순차 전송하므로,
  /// [dispense]가 최종 응답(0x2E/0x2F)까지 블로킹 수신한다.
  /// 완료 후 별도 상태 폴링은 불필요하다.
  ///
  /// [pollInterval]: 하위 호환용, 사용되지 않음.
  /// [overallTimeout]: 배출 전체 타임아웃 (dispense 내부로 전달).
  Future<void> dispenseAndWait({
    required int count,
    required int index,
    required Duration pollInterval,
    required Duration overallTimeout,
  }) async {
    try {
      logger.i('2. CardDispenserManager: dispense index=$index count=$count');
      final ok = await dispense(count, timeout: overallTimeout);
      logger.i('3. CardDispenserManager: dispense result=$ok index=$index');

      if (!ok) {
        final err = await getError();

        if (err.errorCode == 'PAYOUT_WORKING') {
          logger.i('CardDispenserManager: dispense and wait skipped (PAYOUT_WORKING) index=$index');
          return;
        }

        final resetOk = await reset();
        if (!resetOk) {
          logger.w('CardDispenserManager: reset failed (PAYOUT_WORKING) index=$index');
          // throw DispenserException('카드 배출기 초기화 실패. 장치 상태를 확인해 주세요.');
        }

        final msg = err.description ?? '장치가 배출을 거부했습니다. 카드 수량 및 장치 상태를 확인해 주세요.';
        throw DispenserException(msg);
      }

      logger.i('CardDispenserManager: Dispense completed successfully index=$index');
    } catch (e) {
      logger.e('CardDispenserManager: Dispense and wait failed', error: e);
      rethrow;
    }
  }

  /// 에러/타임아웃 시 reset으로 복귀 시도
  Future<void> _stopMotorOnError() async {
    try {
      // await reset();
    } catch (e) {
      logger.w('CardDispenserManager: _stopMotorOnError(reset) failed', error: e);
    }
  }
}
