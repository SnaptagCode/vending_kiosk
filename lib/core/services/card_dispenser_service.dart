import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:vending_kiosk/core/common/logger/logger_service.dart';
import 'package:vending_kiosk/core/services/card_dispenser_manager.dart';

part 'card_dispenser_service.g.dart';

/// High-level workflow for WITH-TECH card dispenser.
///
/// Responsibilities:
/// - Connect / health check
/// - Dispense N cards
/// - Poll status until completed or error/timeout
/// - Fetch error code detail when needed
@Riverpod(keepAlive: true)
class CardDispenserService extends _$CardDispenserService {
  CardDispenserManager? _manager;
  String? _connectedPort;
  int? _connectedBaudRate;

  /// 진행 중인 autoDetect Future — 중복 실행 방지용
  Future<String?>? _autoDetectFuture;

  static const Duration _defaultPollInterval = Duration(milliseconds: 150);
  static const Duration _defaultOverallTimeout = Duration(seconds: 10);

  @override
  CardDispenserServiceState build() {
    ref.onDispose(() async {
      try {
        await disconnect();
      } catch (e) {
        logger.w('CardDispenserService: Failed to disconnect on dispose', error: e);
      }
      _manager = null;
    });
    return const CardDispenserServiceState.idle();
  }

  /// Reads port from dotenv: `CARD_DISPENSER_PORT` e.g. "COM3"
  ///
  /// If missing, returns null.
  String? readConfigFromEnv() {
    final port = dotenv.env['CARD_DISPENSER_PORT']?.trim();
    if (port == null || port.isEmpty) return null;
    return port;
  }

  /// Connects if not connected (or if port/baudRate changed).
  Future<void> ensureConnected({required String port, int baudRate = 9600}) async {
    // isConnected는 serial_port_win32 내부에서 Win32 핸들 접근 시 예외가 발생할 수 있으므로 try-catch로 감쌈
    bool currentlyConnected = false;
    try {
      currentlyConnected =
          _manager != null && _connectedPort == port && _connectedBaudRate == baudRate && _manager!.isConnected;
    } catch (_) {
      currentlyConnected = false;
    }
    if (currentlyConnected) {
      return;
    }

    bool managerDisconnected = false;
    try {
      managerDisconnected = _manager != null && !_manager!.isConnected;
    } catch (_) {
      managerDisconnected = _manager != null; // 예외 시 연결 끊김으로 간주
    }
    if (managerDisconnected) {
      logger.w('AUTODETECTPORT: 이전 연결이 끊긴 상태 감지, 재연결 시도...');
      await CardDispenserManager.disconnectAll();
      _manager = null;
      _connectedPort = null;
      _connectedBaudRate = null;
    }

    state = const CardDispenserServiceState.connecting();

    _manager = await CardDispenserManager.getInstance();
    final ok = await _manager!.connect(port, baudRate: baudRate);

    logger.d('AUTODETECTPORT ensureConnected ok: $ok');
    if (!ok) {
      logger.d('AUTODETECTPORT ensureConnected failed: $port');
      state = CardDispenserServiceState.error('Failed to connect: $port');
      throw CardDispenserServiceException('카드 배출기 연결 실패 ($port)');
    }

    _connectedPort = port;
    _connectedBaudRate = baudRate;

    // 포트 오픈 직후 장치 초기화 대기 (응답 준비 시간)
    await Future<void>.delayed(const Duration(milliseconds: 150));

    logger.d('AUTODETECTPORT ensureConnected healthCheck');
    final healthy = await _manager!.healthCheck();
    logger.d('AUTODETECTPORT ensureConnected healthCheck result: $healthy');
    if (!healthy) {
      logger.d('AUTODETECTPORT ensureConnected healthCheck failed: $port');
      state = CardDispenserServiceState.error('Health check failed: $port');
      throw CardDispenserServiceException('카드 배출기 통신 확인 실패 ($port)');
    }

    state = const CardDispenserServiceState.ready();
  }

  /// 연결된 시리얼 포트 중 카드 배출기를 자동으로 감지하고 연결합니다.
  ///
  /// 동시에 여러 곳에서 호출되더라도 하나의 Future만 실행되며, 나머지는 그 결과를 공유합니다.
  /// (두 호출이 같은 CardDispenserManager 싱글톤을 동시에 조작하는 레이스 컨디션 방지)
  Future<String?> autoDetectPort() {
    _autoDetectFuture ??= _runAutoDetect().whenComplete(() {
      _autoDetectFuture = null;
    });
    return _autoDetectFuture!;
  }

  Future<String?> _runAutoDetect() async {
    state = const CardDispenserServiceState.connecting();
    try {
      final ports = CardDispenserManager.getAvailablePorts();
      if (ports.isEmpty) {
        state = const CardDispenserServiceState.error('사용 가능한 COM 포트 없음');
        return null;
      }

      logger.i('AUTODETECTPORT CardDispenserService.autoDetectPort: scanning ports=$ports');

      for (final port in ports) {
        try {
          await ensureConnected(port: port, baudRate: 9600);
          logger.i('AUTODETECTPORT CardDispenserService.autoDetectPort: found $port @ 9600bps');
          return port;
        } catch (e) {
          logger.d('AUTODETECTPORT CardDispenserService.autoDetectPort: $port @ 9600bps failed – $e');
          await CardDispenserManager.disconnectAll();
          _manager = null;
          _connectedPort = null;
          _connectedBaudRate = null;
          await Future<void>.delayed(const Duration(milliseconds: 500));
        }
      }

      state = const CardDispenserServiceState.error('배출기를 감지하지 못했습니다');
      return null;
    } catch (e) {
      state = CardDispenserServiceState.error('자동 감지 실패: $e');
      return null;
    }
  }

  Future<void> disconnect() async {
    await CardDispenserManager.disconnectAll();
  }

  /// 동작 금지(Disable) — WITH-TECH에서는 reset으로 처리.
  Future<bool> disableDispenser() async {
    if (_manager == null || !_manager!.isConnected) return false;
    try {
      return await _manager!.disable();
    } catch (e) {
      logger.w('CardDispenserService: disableDispenser failed', error: e);
      return false;
    }
  }

  /// 카드 배출기 초기화(Reset).
  Future<bool> resetDispenser() async {
    if (_manager == null || !_manager!.isConnected) return false;
    try {
      return await _manager!.reset();
    } catch (e) {
      logger.w('CardDispenserService: resetDispenser failed', error: e);
      return false;
    }
  }

  /// 다음 배출이 가능할 때까지 대기 (상태가 standby가 될 때까지 폴링).
  Future<void> waitUntilStandby({
    Duration pollInterval = const Duration(milliseconds: 100),
    Duration timeout = const Duration(seconds: 5),
  }) async {
    if (_manager == null || !_manager!.isConnected) return;
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      final status = await _manager!.getStatus();
      if (status == 'standby') return;
      await Future.delayed(pollInterval);
    }
    logger.w('CardDispenserService: waitUntilStandby timed out after ${timeout.inSeconds}s');
  }

  /// Dispense [count] cards and wait until completion.
  ///
  /// Throws [CardDispenserServiceException] on timeout or hardware error.
  Future<void> dispenseAndWait({
    required int count,
    Duration pollInterval = _defaultPollInterval,
    Duration overallTimeout = _defaultOverallTimeout,
  }) async {
    // Only meaningful on Windows (serial_port_win32).
    if (!defaultTargetPlatform.toString().toLowerCase().contains('windows')) {
      logger.w('CardDispenser: skip dispense (not Windows)');
      return;
    }

    // 연결 안 됐으면 자동 감지 시도
    if (!CardDispenserManager.isInstanceConnected) {
      logger.i('CardDispenserService dispenseAndWait: 연결 안 됨 → 자동 감지 시도');
      final detected = await autoDetectPort();
      if (detected == null) {
        logger.w('CardDispenser: skip dispense (자동 감지 실패)');
        return;
      }
    }

    state = CardDispenserServiceState.dispensing(count);

    try {
      await _manager!.dispenseAndWait(
        count: count,
        pollInterval: pollInterval,
        overallTimeout: overallTimeout,
      );
      state = const CardDispenserServiceState.ready();
    } catch (e) {
      state = CardDispenserServiceState.error(e.toString());
      throw CardDispenserServiceException('카드 배출 실패: $e');
    }
  }
}

sealed class CardDispenserServiceState {
  const CardDispenserServiceState();

  const factory CardDispenserServiceState.idle() = _Idle;
  const factory CardDispenserServiceState.connecting() = _Connecting;
  const factory CardDispenserServiceState.ready() = _Ready;
  const factory CardDispenserServiceState.dispensing(int count) = _Dispensing;
  const factory CardDispenserServiceState.error(String message) = _ServiceError;

  /// Pattern matching helper
  T when<T>({
    required T Function() idle,
    required T Function() connecting,
    required T Function() ready,
    required T Function(int count) dispensing,
    required T Function(String message) error,
  }) {
    final state = this;
    if (state is _Idle) return idle();
    if (state is _Connecting) return connecting();
    if (state is _Ready) return ready();
    if (state is _Dispensing) return dispensing(state.count);
    if (state is _ServiceError) return error(state.message);
    throw Exception('Unknown state: $state');
  }

  /// Simplified when (ignores parameters)
  T maybeWhen<T>({
    T Function()? idle,
    T Function()? connecting,
    T Function()? ready,
    T Function(int count)? dispensing,
    T Function(String message)? error,
    required T Function() orElse,
  }) {
    final state = this;
    if (state is _Idle && idle != null) return idle();
    if (state is _Connecting && connecting != null) return connecting();
    if (state is _Ready && ready != null) return ready();
    if (state is _Dispensing && dispensing != null) return dispensing(state.count);
    if (state is _ServiceError && error != null) return error(state.message);
    return orElse();
  }
}

class _Idle extends CardDispenserServiceState {
  const _Idle();
}

class _Connecting extends CardDispenserServiceState {
  const _Connecting();
}

class _Ready extends CardDispenserServiceState {
  const _Ready();
}

class _Dispensing extends CardDispenserServiceState {
  final int count;
  const _Dispensing(this.count);
}

class _ServiceError extends CardDispenserServiceState {
  final String message;
  const _ServiceError(this.message);
}

class CardDispenserServiceException implements Exception {
  final String message;
  CardDispenserServiceException(this.message);

  @override
  String toString() => message;
}
