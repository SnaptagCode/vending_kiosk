import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:vending_kiosk/core/common/logger/logger_service.dart';
import 'package:vending_kiosk/core/services/card_dispenser_manager.dart';

part 'card_dispenser_service.g.dart';

/// High-level workflow for ONEPLUS card dispenser.
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
  String? _connectedProtocol;

  static const Duration _defaultPollInterval = Duration(milliseconds: 150);
  static const Duration _defaultOverallTimeout = Duration(seconds: 2);

  @override
  CardDispenserServiceState build() {
    ref.onDispose(() async {
      // 앱 종료 시 포트를 명시적으로 정리하여 재시작 시 정상 연결 보장
      try {
        await disconnect();
      } catch (e) {
        logger.w('CardDispenserService: Failed to disconnect on dispose', error: e);
      }
      _manager = null;
    });
    return const CardDispenserServiceState.idle();
  }

  /// Reads port/protocol from dotenv:
  /// - `CARD_DISPENSER_PORT` e.g. "COM3"
  /// - `CARD_DISPENSER_PROTOCOL` either "txUpperRxLower" or "txLowerRxLower"
  ///
  /// If missing, returns null.
  ({String port, String protocol})? readConfigFromEnv() {
    final port = dotenv.env['CARD_DISPENSER_PORT']?.trim();
    if (port == null || port.isEmpty) return null;

    final protoRaw = (dotenv.env['CARD_DISPENSER_PROTOCOL'] ?? '').trim();
    final protocol = switch (protoRaw) {
      'txLowerRxLower' => 'txLowerRxLower',
      'txUpperRxLower' || '' => 'txUpperRxLower',
      _ => 'txUpperRxLower',
    };

    return (port: port, protocol: protocol);
  }

  /// Connects if not connected (or if port/protocol changed).
  /// 매니저가 이미 끊긴 상태(disconnectAll 등)면 재연결합니다.
  Future<void> ensureConnected({
    required String port,
    String protocol = 'txUpperRxLower',
  }) async {
    final alreadyConnected =
        _manager != null && _connectedPort == port && _connectedProtocol == protocol && _manager!.isConnected;
    if (alreadyConnected) {
      return;
    }

    state = const CardDispenserServiceState.connecting();

    _manager = await CardDispenserManager.getInstance();
    final ok = await _manager!.connect(port, protocol);

    logger.d('CardDispenserService ensureConnected ok: $ok');
    if (!ok) {
      logger.d('CardDispenserService ensureConnected failed: $port');
      state = CardDispenserServiceState.error('Failed to connect: $port');
      throw CardDispenserServiceException('카드 배출기 연결 실패 ($port)');
    }

    _connectedPort = port;
    _connectedProtocol = protocol;

    logger.d('CardDispenserService ensureConnected healthCheck');
    final healthy = await _manager!.healthCheck();
    logger.d('CardDispenserService ensureConnected healthCheck result: $healthy');
    if (!healthy) {
      logger.d('CardDispenserService ensureConnected healthCheck failed: $port');
      state = CardDispenserServiceState.error('Health check failed: $port');
      throw CardDispenserServiceException('카드 배출기 통신 확인 실패 ($port)');
    }

    state = const CardDispenserServiceState.ready();
  }

  Future<void> disconnect() async {
    await CardDispenserManager.disconnectAll();
  }

  /// 동작 금지(Disable) — 배출 중인 모터를 멈춤. 카드 부족 등 에러 시 먼저 호출.
  Future<bool> disableDispenser() async {
    if (_manager == null || !_manager!.isConnected) return false;
    try {
      return await _manager!.disable();
    } catch (e) {
      logger.w('CardDispenserService: disableDispenser failed', error: e);
      return false;
    }
  }

  /// 카드 배출기 초기화(Reset). 프린터 에러 등 발생 시 호출하여 배출기를 초기 상태로 복귀시킴.
  /// 연결되어 있지 않으면 아무 동작 없이 false 반환.
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
  /// 고정 대기 대신 기기가 준비되는 즉시 다음 배출을 시도해 최소 대기시간으로 연속 배출할 수 있음.
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
    String? port,
    String protocol = 'txUpperRxLower',
    Duration pollInterval = _defaultPollInterval,
    Duration overallTimeout = _defaultOverallTimeout,
  }) async {
    final cfg = port == null ? readConfigFromEnv() : null;
    final resolvedPort = port ?? cfg?.port;
    final resolvedProtocol = port != null ? protocol : (cfg?.protocol ?? protocol);
    logger.d('CardDispenserService dispenseAndWait resolvedPort: $resolvedPort, resolvedProtocol: $resolvedProtocol');

    if (resolvedPort == null || resolvedPort.isEmpty) {
      // No config: don't block print flow unless explicitly configured.
      logger.w('CardDispenser: skip dispense (no port configured)');
      return;
    }

    // Only meaningful on Windows (serial_port_win32).
    if (!defaultTargetPlatform.toString().toLowerCase().contains('windows')) {
      logger.w('CardDispenser: skip dispense (not Windows)');
      return;
    }

    await ensureConnected(port: resolvedPort, protocol: resolvedProtocol);

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
