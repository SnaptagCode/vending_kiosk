import 'dart:async';

import 'package:vending_kiosk/core/common/logger/logger_service.dart';
import 'package:vending_kiosk/core/data/datasources/local/card_dispenser_protocol.dart';
import 'package:vending_kiosk/core/data/datasources/local/card_dispenser_serial.dart';

/// Manager for card dispenser operations (runs on main isolate for reliable COM port open on Windows).
class CardDispenserManager {
  static CardDispenserManager? _instance;

  CardDispenserSerial? _serial;
  String? _connectedPort;
  CardDispenserProtocol? _connectedProtocol;

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
  /// 재실행 시 포트가 정상적으로 열리도록 합니다.
  static Future<void> disconnectAll() async {
    if (_instance == null) return;
    try {
      if (_instance!._serial != null) {
        await _instance!._serial!.disconnect();
        _instance!._serial = null;
      }
      _instance!._connectedPort = null;
      _instance!._connectedProtocol = null;
      logger.i('CardDispenserManager: Disconnected and cleared');
    } catch (e) {
      logger.w('CardDispenserManager: disconnectAll error', error: e);
    } finally {
      _instance = null;
    }
  }

  /// 실제 시리얼 연결 여부 (재연결 필요 여부 판단용)
  bool get isConnected => _serial != null && _serial!.isConnected;

  /// Connect to card dispenser (must run on main isolate for Windows COM port).
  Future<bool> connect(String port, String protocol) async {
    try {
      final proto =
          protocol == 'txLowerRxLower' ? CardDispenserProtocol.txLowerRxLower : CardDispenserProtocol.txUpperRxLower;

      // 포트/프로토콜 변경 시 또는 이미 끊긴 상태면 기존 시리얼을 먼저 닫음.
      // (닫지 않으면 COM 포트가 같은 프로세스에 잡힌 채로 재연결 시 Error 5 발생)
      if (_serial != null) {
        if (_connectedPort != port || _connectedProtocol != proto || !_serial!.isConnected) {
          logger.d('CardDispenserManager: Disconnecting previous serial connection...');
          await _serial!.disconnect();
          _serial = null;
          _connectedPort = null;
          _connectedProtocol = null;
          // 포트 리소스 완전 해제를 위한 추가 대기
          await Future<void>.delayed(const Duration(milliseconds: 200));
        }
      }

      if (_serial == null || !_serial!.isConnected) {
        logger.d('CardDispenserManager: Creating new CardDispenserSerial instance...');
        _serial = CardDispenserSerial(protocol: proto);
        final connected = await _serial!.connect(port);

        if (connected) {
          _connectedPort = port;
          _connectedProtocol = proto;
          logger.i('CardDispenserManager: Connected to $port');
          return true;
        } else {
          final available = CardDispenserSerial.getAvailablePorts();
          logger.e('CardDispenserManager: 연결 실패 - 요청된 포트: $port, 사용 가능한 포트: $available');
          _serial = null; // 연결 실패 시 인스턴스 제거
          throw Exception(
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
      logger.e('CardDispenserManager: Connect failed', error: e);
      // 연결 실패 시 상태 완전 초기화
      _serial = null;
      _connectedPort = null;
      _connectedProtocol = null;
      rethrow;
    }
  }

  /// Health check
  Future<bool> healthCheck() async {
    if (_serial == null || !_serial!.isConnected) {
      throw Exception('Not connected');
    }
    return _serial!.healthCheck();
  }

  /// 초기화(Reset) — 배출기를 초기 상태로 복귀. 프린터 에러 등 발생 시 호출 권장.
  Future<bool> reset() async {
    if (_serial == null || !_serial!.isConnected) {
      logger.d('CardDispenserManager: reset skipped (not connected)');
      return false;
    }
    try {
      final ok = await _serial!.reset();
      if (ok)
        logger.i('CardDispenserManager: Dispenser reset OK');
      else {
        logger.w('CardDispenserManager: Dispenser reset returned false (device busy or error)');
      }
      return ok;
    } catch (e) {
      logger.w('CardDispenserManager: reset failed', error: e);
      return false;
    }
  }

  /// 동작 금지(Disable) — 배출 중인 모터를 멈춤. 카드 부족 등 에러 시 먼저 호출 권장.
  Future<bool> disable() async {
    if (_serial == null || !_serial!.isConnected) {
      logger.d('CardDispenserManager: disable skipped (not connected)');
      return false;
    }
    try {
      final ok = await _serial!.disable();
      if (ok) {
        logger.i('CardDispenserManager: Dispenser disabled (motor stop)');
      } else {
        logger.w('CardDispenserManager: Disable returned false');
      }
      return ok;
    } catch (e) {
      logger.w('CardDispenserManager: disable failed', error: e);
      return false;
    }
  }

  /// 동작 금지 해제(Enable) — 다음 배출 전에 금지 상태를 풀 때 사용.
  Future<bool> enable() async {
    if (_serial == null || !_serial!.isConnected) {
      logger.d('CardDispenserManager: enable skipped (not connected)');
      return false;
    }
    try {
      final ok = await _serial!.enable();
      if (ok)
        logger.i('CardDispenserManager: Dispenser enabled');
      else
        logger.w('CardDispenserManager: Enable returned false');
      return ok;
    } catch (e) {
      logger.w('CardDispenserManager: enable failed', error: e);
      return false;
    }
  }

  /// Dispense cards
  Future<bool> dispense(int count) async {
    if (_serial == null || !_serial!.isConnected) {
      throw Exception('Not connected');
    }
    return _serial!.dispenseCard(count);
  }

  /// Get status (standby, dispensing, completed, error, unknown, disabled)
  Future<String> getStatus() async {
    if (_serial == null || !_serial!.isConnected) {
      throw Exception('Not connected');
    }

    final status = await _serial!.getStatus();
    return status.kind.name;
  }

  /// Get error details
  Future<({String? description, String? errorCode})> getError() async {
    if (_serial == null || !_serial!.isConnected) {
      throw Exception('Not connected');
    }
    final error = await _serial!.getError();
    return (description: error?.description, errorCode: error?.errorCode);
  }

  /// Dispense and wait until completion
  Future<void> dispenseAndWait({
    required int count,
    required Duration pollInterval,
    required Duration overallTimeout,
  }) async {
    try {
      logger.i('CardDispenserManager: Starting dispense and wait for $count card(s)...');

      // 이전 에러로 동작 금지 상태일 수 있으므로 해제 시도
      await enable();

      final ok = await dispense(count);
      if (!ok) {
        await _stopMotorOnError();
        final err = await getError();
        final msg = err.description ?? '장치가 배출을 거부했습니다(불능). 배출 간 대기 시간 후 다시 시도해 주세요.';
        throw Exception('Dispense failed: $msg');
      }

      final deadline = DateTime.now().add(overallTimeout);
      while (DateTime.now().isBefore(deadline)) {
        final status = await getStatus();

        logger.d('CardDispenserManager: Status: $status');

        switch (status) {
          case 'completed':
            logger.i('CardDispenserManager: Dispense completed successfully');
            return;
          case 'dispensing':
            break;
          case 'standby':
            logger.i('CardDispenserManager: Dispense completed (standby)');
            return;
          case 'disabled':
            throw Exception('Device is disabled');
          case 'error':
          case 'unknown':
            await _stopMotorOnError();
            final err = await getError();
            final msg = err.description ?? '장치 오류(에러 코드 없음). 카드 걸림/부족 등을 확인해 주세요.';
            throw Exception('Dispenser error: $msg');
        }

        await Future.delayed(pollInterval);
      }

      await _stopMotorOnError();
      throw Exception('Dispense timeout after ${overallTimeout.inSeconds} seconds');
    } catch (e) {
      logger.e('CardDispenserManager: Dispense and wait failed', error: e);
      rethrow;
    }
  }

  /// 에러/타임아웃 시 모터 정지를 위해 동작 금지(Disable) 전송. 실패해도 로그만 남김.
  Future<void> _stopMotorOnError() async {
    try {
      await disable();
    } catch (e) {
      logger.w('CardDispenserManager: _stopMotorOnError failed', error: e);
    }
  }
}
