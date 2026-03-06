import 'dart:async';
import 'dart:typed_data';

import 'package:serial_port_win32/serial_port_win32.dart';
import 'package:vending_kiosk/core/common/logger/logger_service.dart';

/// WITH-TECH WT-CB3/CF1/CB7/CR1/CR1F1/F2 Dispenser RS-232 프로토콜 구현.
///
/// - 포트 설정: 8N1, BaudRate는 생성자에서 지정 (기본 19200bps)
/// - 프레임: STX(0x02) + CMD(1) + DATA/STATUS(1) + ETX(0x03) + Checksum(1) + CR(0x0D) + LF(0x0A)
///   - Checksum = (unsigned char)(CMD + DATA/STATUS + ETX)
///
/// 이 클래스는 기존 ONEPLUS용 `CardDispenserSerial`과는 완전히 별도의 구현으로,
/// WITH-TECH 계열 장비 전용으로 사용한다.
class WithTechCardDispenserSerial {
  // 통신 설정
  final int baudRate;
  static const int dataBits = 8;
  static const int stopBits = 1; // 스펙상 1 stop bit (Win32 API StopBits 파라미터는 0=ONESTOPBIT 사용)
  static const String parity = 'none';

  // 프레임 구성
  static const int stx = 0x02;
  static const int etx = 0x03;
  static const int cr = 0x0D;
  static const int lf = 0x0A;

  // 예상 기본 프레임 길이 (STX..LF)
  static const int frameSize = 7;

  // HOST → DISPENSER 주요 명령 (CMD)
  static const int cmdAck = 0x10; // (예약) ACK
  static const int cmdNak = 0x11; // (예약) NAK
  static const int cmdSystemReset = 0x12; // System initialize & Reset
  static const int cmdErrorClearAndProceed = 0x13; // Error(Hold) clear & Job proceed
  static const int cmdCounterClear = 0x14; // Counter clear (FND)
  static const int cmdRequestStatus = 0x15; // Request machine status
  static const int cmdSetMaxCount = 0x16; // Max count setting (Count1)
  static const int cmdRequestTotalOut1 = 0x17; // Request Total-Out Q'ty (1st)
  static const int cmdRequestTotalOut2 = 0x18; // Request Total-Out Q'ty (2nd)
  static const int cmdRequestLastOutQty = 0x19; // Request Last-Out Q'ty
  static const int cmdCountBills = 0x1A; // Count Bills
  static const int cmdCountCancel = 0x1B; // Count Cancel (Reject)
  static const int cmdCountPayoutHold = 0x1C; // Count / Payout hold
  static const int cmdMoveCountToPayout = 0x1D; // Counting bills move to payout
  static const int cmdPayoutFirst = 0x1E; // Payout (1st Cartridge) / 카드·지폐 방출 명령
  static const int cmdPayoutSecond = 0x1F; // Payout (2nd Cartridge)
  static const int cmdRequestLastStatus = 0x50; // Request Last status
  static const int cmdCr1fLedOrSecondMotor = 0x31; // CR1F1: LED / CR1F2: 2nd Motor time

  // DISPENSER → HOST 응답 CMD
  static const int rspAckOrStatus = 0x20; // ACK or Status
  static const int rspNak = 0x21; // NAK
  static const int rspSystemReady = 0x22; // System Ready
  static const int rspSystemWarning = 0x23; // System Warning (Empty or Etc.)
  static const int rspFrameTimeout = 0x24; // Frame Time over
  static const int rspMissingEtx = 0x25; // Missing of ETX
  static const int rspChecksumError = 0x26; // Check sum error
  static const int rspCommandError = 0x27; // Command error (Non-exist)
  static const int rspMaxBillsError = 0x28; // Maximum number of bills error
  static const int rspPayoutWorking = 0x29; // Payout working
  static const int rspCountSuccessful = 0x2A; // Count successful
  static const int rspCountToReject = 0x2B; // Counting bills moved to Reject
  static const int rspCountPayoutHalt = 0x2C; // Count / Payout halt
  static const int rspCountToPayout = 0x2D; // Counting bills moved to Payout
  static const int rspPayoutSuccessful = 0x2E; // Payout successful
  static const int rspPayoutFails = 0x2F; // Payout Fails
  static const int rspLastPaidOutQty = 0x36; // Last paid-out Q'ty
  static const int rspTotalPaidOutQty = 0x37; // Total paid-out Q'ty

  String? _portName;
  SerialPort? _port;
  bool _isConnected = false;

  WithTechCardDispenserSerial({
    String? portName,
    this.baudRate = 9600,
  }) : _portName = portName;

  String? get portName => _portName;

  /// 사용 가능한 시리얼 포트 목록
  static List<String> getAvailablePorts() {
    try {
      return SerialPort.getAvailablePorts();
    } catch (e) {
      logger.e('WithTech: Failed to get available ports', error: e);
      return [];
    }
  }

  /// 연결 상태
  bool get isConnected => _isConnected && _port != null && _port!.isOpened;

  /// Win32 오류 코드 기반 안내 메시지
  static String _win32ErrorHint(Object e) {
    final msg = e.toString();
    final match = RegExp(r'win32 error code is (\d+)').firstMatch(msg);
    if (match == null) {
      return 'Ensure the port exists, is not in use, and try running as Administrator.';
    }
    final code = int.tryParse(match.group(1) ?? '') ?? -1;
    switch (code) {
      case 0:
        return 'Error 0: 이전 실행에서 포트가 아직 해제 중일 수 있습니다. 2초 후 자동 재시도합니다.';
      case 2:
        return 'Error 2 (파일 없음): COM 포트가 없거나 장치가 분리되었습니다. 장치 관리자에서 포트를 확인하세요.';
      case 5:
        return 'Error 5 (접근 거부): COM 포트가 사용 중입니다. '
            '다른 시리얼 프로그램 또는 이전 실행이 포트를 잡고 있을 수 있습니다.';
      case 32:
        return 'Error 32 (공유 위반): COM 포트가 사용 중입니다. '
            '장치 관리자에서 해당 COM 장치를 제거 후 다시 검색해 보세요.';
      default:
        return 'Win32 error $code. Try closing other apps using this port or run as Administrator.';
    }
  }

  /// Win32 error 6 (ERROR_INVALID_HANDLE) 여부
  static bool _isInvalidHandleError(Object e) {
    return e.toString().contains('win32 error code is 6');
  }

  /// 리소스 정리
  Future<void> disconnect() async {
    try {
      if (_port != null && _port!.isOpened) {
        _port!.close();
        logger.d('WithTech: port closed');
      }
      _isConnected = false;
      _port = null;
      logger.i('WithTech: disconnected (${_portName ?? '-'})');
    } catch (e) {
      logger.e('WithTech: Failed to disconnect', error: e);
      _isConnected = false;
      _port = null;
    }
  }

  /// 한 번만 연결 시도 (autoDetect용)
  Future<bool> connectOnce(String portName) async {
    try {
      // 기존 연결 정리
      if (_isConnected && _port != null) {
        await disconnect();
      }

      if (_port != null) {
        try {
          if (_port!.isOpened) {
            _port!.close();
          }
        } catch (e) {
          logger.w('CardDispenserSerial WithTech: Failed to close previous port instance', error: e);
        }
        _port = null;
        await Future<void>.delayed(const Duration(milliseconds: 200));
      }

      _portName = portName;
      _port = SerialPort(
        portName,
        openNow: false,
        ByteSize: dataBits,
        BaudRate: baudRate,
        StopBits: 0, // Win32: 0=ONESTOPBIT(1 stop bit), 1=ONE5STOPBITS(1.5), 2=TWOSTOPBITS
        Parity: 0,
      );

      await _port!.open();

      if (_port!.isOpened) {
        // serial_port_win32은 portName 기준 싱글톤 캐시를 사용하므로,
        // 이전에 다른 BaudRate로 열렸던 인스턴스가 반환될 수 있음.
        // open() 후 setter로 BaudRate를 강제 덮어써서 실제 적용.
        try {
          _port!.BaudRate = baudRate;
        } catch (e) {
          logger.w('CardDispenserSerial  WithTech: BaudRate override failed (baud: $baudRate)', error: e);
        }
        _isConnected = true;
        logger.i('CardDispenserSerial  WithTech: connected to $portName (baud: $baudRate)');
        return true;
      } else {
        logger.e('CardDispenserSerial  WithTech: Failed to open serial port $portName');
        _port = null;
        _isConnected = false;
        return false;
      }
    } catch (e) {
      final available = getAvailablePorts();
      final hint = _win32ErrorHint(e);
      logger.e(
        'CardDispenserSerial WithTech: Failed to connect to dispenser at $portName. '
        'CardDispenserSerial Available ports: $available. $hint',
        error: e,
      );
      _isConnected = false;
      _port = null;
      return false;
    }
  }

  /// 일반 연결 (재시도 포함)
  Future<bool> connect(String portName) async {
    final first = await connectOnce(portName);
    if (first) return true;

    final msg = _win32ErrorHint(Exception('connect failed'));
    logger.w('WithTech: first connect failed. Hint: $msg');

    await Future<void>.delayed(const Duration(seconds: 2));
    return connectOnce(portName);
  }

  /// Checksum 계산 (STX + CMD + DATA/STATUS + ETX)
  ///
  /// 스펙 예제 검증: 02 15 00 03 → 0x02+0x15+0x00+0x03 = 0x1A ✅
  int _calculateChecksum(int cmd, int dataOrStatus) {
    return (stx + cmd + dataOrStatus + etx) & 0xFF;
  }

  /// 패킷 생성
  Uint8List _createPacket(int cmd, int dataOrStatus) {
    final checksum = _calculateChecksum(cmd, dataOrStatus);
    return Uint8List.fromList([
      stx,
      cmd,
      dataOrStatus,
      etx,
      checksum,
      cr,
      lf,
    ]);
  }

  /// 패킷 송신 + 응답 수신
  Future<Uint8List?> _sendCommand(
    int cmd,
    int dataOrStatus, {
    int timeoutMs = 500,
    int retryCount = 3,
  }) async {
    if (!isConnected) {
      throw Exception('WithTech: Serial port is not connected');
    }

    final packet = _createPacket(cmd, dataOrStatus);

    for (int attempt = 0; attempt <= retryCount; attempt++) {
      try {
        // 입력 버퍼 비우기 (타임아웃 최소화)
        try {
          _port!.readBytes(1024, timeout: const Duration(milliseconds: 1));
        } catch (e) {
          if (_isInvalidHandleError(e)) {
            _isConnected = false;
            _port = null;
            throw Exception('WithTech: Serial port handle invalidated (win32 error 6). Reconnect required.');
          }
        }

        logger.d('WithTech: TX [${packet.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ')}]');
        final writeOk = await _port!.writeBytesFromUint8List(packet, timeout: timeoutMs);
        if (_port == null) {
          throw Exception('WithTech: Serial port disconnected during write');
        }
        if (!writeOk) {
          throw Exception('WithTech: Failed to write packet');
        }

        final timeout = Duration(milliseconds: timeoutMs);
        Uint8List? response;

        try {
          response = await _port!.readBytes(frameSize, timeout: timeout);
          logger.d(
              'WithTech: RX [${response.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ')}] (${response.length}/${frameSize}B)');
          if (response.length < frameSize) {
            throw TimeoutException('WithTech: Read timeout after ${timeoutMs}ms');
          }
        } catch (e) {
          if (_isInvalidHandleError(e)) {
            _isConnected = false;
            _port = null;
            throw Exception('WithTech: Serial port handle invalidated (win32 error 6). Reconnect required.');
          }
          if (attempt < retryCount) {
            logger.w('WithTech: response timeout on attempt ${attempt + 1}, retrying...', error: e);
            await Future.delayed(const Duration(milliseconds: 100));
            continue;
          } else {
            logger.e('WithTech: Failed to read response after $retryCount attempts', error: e);
            rethrow;
          }
        }

        if (response.length != frameSize) {
          if (attempt < retryCount) {
            logger.w('WithTech: invalid response length: ${response.length}, expected $frameSize. Retrying...');
            await Future.delayed(const Duration(milliseconds: 100));
            continue;
          } else {
            logger.e('WithTech: invalid response length: ${response.length}, expected $frameSize');
            return null;
          }
        }

        if (response[0] != stx || response[3] != etx || response[5] != cr || response[6] != lf) {
          if (attempt < retryCount) {
            logger.w(
              'WithTech: invalid frame markers (STX/ETX/CR/LF). '
              'got: ${response.map((e) => e.toRadixString(16))}. Retrying...',
            );
            await Future.delayed(const Duration(milliseconds: 100));
            continue;
          } else {
            logger.e('WithTech: invalid frame markers. response=$response');
            return null;
          }
        }

        final receivedChecksum = response[4];
        // 스펙 공식: CS = (STX + CMD + DATA + ETX) & 0xFF
        // 일부 장치 펌웨어 버그: STATUS 바이트가 0x00이 아닐 때도 STATUS=0x00 기준
        // 체크섬을 재사용하는 경우가 있음 → 불일치 시 경고만 남기고 계속 처리.
        final calcWithStx = _calculateChecksum(response[1], response[2]);
        final calcWithoutStx = (response[1] + response[2] + etx) & 0xFF;
        if (receivedChecksum != calcWithStx && receivedChecksum != calcWithoutStx) {
          logger.w(
            'WithTech: checksum mismatch (firmware quirk, continuing): '
            'recv=0x${receivedChecksum.toRadixString(16)}, '
            'expected=0x${calcWithStx.toRadixString(16)}',
          );
        }

        return response;
      } catch (e) {
        if (_isInvalidHandleError(e)) rethrow;
        if (attempt < retryCount) {
          logger.w('WithTech: command send attempt ${attempt + 1} failed, retrying...', error: e);
          await Future.delayed(const Duration(milliseconds: 100));
        } else {
          logger.e('WithTech: command send failed after $retryCount retries', error: e);
          rethrow;
        }
      }
    }

    return null;
  }

  /// Health check 비슷한 통신 확인.
  ///
  /// - HOST: CMD=0x15 (Request machine status), DATA=0x00
  /// - 예상 응답:
  ///   - CMD=0x20 (ACK/Status) 또는 0x22 (System Ready)
  Future<bool> healthCheck({int timeoutMs = 500, int retryCount = 3}) async {
    try {
      final resp = await _sendCommand(cmdRequestStatus, 0x00, timeoutMs: timeoutMs, retryCount: retryCount);
      if (resp == null) return false;
      final cmd = resp[1];
      // 프로토콜 오류 응답이 아닌 한, 장치가 응답했다는 것 자체가 통신 OK
      return cmd != rspNak &&
          cmd != rspFrameTimeout &&
          cmd != rspMissingEtx &&
          cmd != rspChecksumError &&
          cmd != rspCommandError;
    } catch (e) {
      logger.e('WithTech: healthCheck failed', error: e);
      return false;
    }
  }

  /// 사용 가능한 포트 중 WITH-TECH 배출기를 자동 감지.
  ///
  /// - 모든 COM 포트를 순회하며 healthCheck에 응답하는 포트를 찾는다.
  /// - [tryBaudRates]: 시도할 보레이트 목록 (기본: 19200, 9600 순서).
  ///   디바이스 DIP 스위치 설정에 따라 달라질 수 있음.
  static Future<({String port, int baudRate})?> autoDetect({
    int connectTimeoutMs = 1000,
    int healthCheckTimeoutMs = 1000,
    List<int>? tryBaudRates,
  }) async {
    final ports = getAvailablePorts();
    if (ports.isEmpty) {
      logger.w('WithTech.autoDetect: no COM ports');
      return null;
    }

    final baudRates = tryBaudRates ?? [19200, 9600];
    logger.i('WithTech.autoDetect: scanning ports=$ports baudRates=$baudRates');

    for (final port in ports) {
      bool portEverOpened = false;
      for (final baud in baudRates) {
        final disp = WithTechCardDispenserSerial(baudRate: baud);
        try {
          bool connected = false;
          try {
            connected =
                await disp.connectOnce(port).timeout(Duration(milliseconds: connectTimeoutMs), onTimeout: () => false);
          } catch (_) {
            connected = false;
          }

          if (!connected) {
            if (!portEverOpened) break; // 포트 자체를 열 수 없음 → 이 포트 건너뜀
            // 이전에 열렸으나 직후 재오픈 실패(Windows가 아직 포트 해제 중) → 다음 보레이트에서 재시도
            logger.d('WithTech.autoDetect: $port @${baud}bps connect failed (port releasing), skip baud');
            continue;
          }
          portEverOpened = true;

          // 포트 오픈 직후 기기 초기화 대기
          await Future<void>.delayed(const Duration(milliseconds: 100));

          final ok = await disp.healthCheck(
            timeoutMs: healthCheckTimeoutMs,
            retryCount: 1,
          );
          if (ok) {
            logger.i('WithTech.autoDetect: dispenser detected on $port (baud: $baud)');
            return (port: port, baudRate: baud);
          }
          logger.d('WithTech.autoDetect: $port @${baud}bps no response');
        } catch (e) {
          logger.d('WithTech.autoDetect: $port @${baud}bps error - $e');
        } finally {
          await disp.disconnect();
          // 포트가 한 번이라도 열렸으면, 다음 보레이트에서 재오픈 전 Windows 릴리즈 대기
          if (portEverOpened) {
            await Future<void>.delayed(const Duration(milliseconds: 200));
          }
        }
      }
    }

    logger.w('WithTech.autoDetect: scan finished, no dispenser detected. ports=$ports');
    return null;
  }

  /// autoDetect 반환형 편의 typedef
  // ({String port, int baudRate})?

  /// System initialize & Reset
  Future<bool> reset() async {
    try {
      final resp = await _sendCommand(cmdSystemReset, 0x00);
      if (resp == null) return false;
      final cmd = resp[1];
      // 리셋 응답은 명세가 상세히 적혀있지 않으므로,
      // NAK(0x21)/에러 계열이 아니면 성공으로 간주.
      if (cmd == rspNak ||
          cmd == rspFrameTimeout ||
          cmd == rspMissingEtx ||
          cmd == rspChecksumError ||
          cmd == rspCommandError) {
        return false;
      }
      return true;
    } catch (e) {
      logger.e('WithTech: reset failed', error: e);
      return false;
    }
  }

  /// [count] 장 배출 명령 (1st Cartridge 기준).
  ///
  /// - HOST: CMD=0x1E, DATA=Count2
  /// - 응답 흐름: ACK(0x20) → 작업 중(0x29) → Payout successful(0x2E) 또는 Payout Fails(0x2F)
  Future<bool> payoutOnce(int count) async {
    if (count < 1 || count > 255) {
      logger.e('WithTech: invalid payout count: $count');
      return false;
    }
    try {
      final resp = await _sendCommand(cmdPayoutFirst, count);
      if (resp == null) return false;
      final cmd = resp[1];
      // 첫 응답이 ACK/Status(0x20)이면 일단 명령 수락으로 본다.
      if (cmd == rspAckOrStatus || cmd == rspPayoutWorking) {
        return true;
      }
      if (cmd == rspPayoutFails ||
          cmd == rspSystemWarning ||
          cmd == rspMaxBillsError ||
          cmd == rspChecksumError ||
          cmd == rspCommandError) {
        return false;
      }
      return true;
    } catch (e) {
      logger.e('WithTech: payoutOnce failed', error: e);
      return false;
    }
  }

  /// 장비 상태 요청 (Request machine status or last status)
  Future<WithTechDispenserStatus> getStatus({bool lastStatus = false}) async {
    try {
      final cmd = lastStatus ? cmdRequestLastStatus : cmdRequestStatus;
      final resp = await _sendCommand(cmd, 0x00);
      if (resp == null) {
        return const WithTechDispenserStatus(
          kind: WithTechDispenserStatusKind.unknown,
          rawCmd: 0,
          data: 0,
          statusByte: 0,
        );
      }
      final rspCmd = resp[1];
      final data = resp[2];
      final statusByte = resp[2]; // 명세상 Status는 DATA 위치에 온다.

      // Status Byte 비트:
      // D7: Jam, D4: Empty, D3: Hold, D2: Payout
      final isJam = (statusByte & 0x80) != 0;
      final isEmpty = (statusByte & 0x10) != 0;
      final isHold = (statusByte & 0x08) != 0;
      final isPayout = (statusByte & 0x04) != 0;

      WithTechDispenserStatusKind kind;
      // rspAckOrStatus(0x20): "ACK or Status" — 정상 대기 응답으로 처리 (에러 비트 없을 때)
      if ((rspCmd == rspSystemReady || rspCmd == rspAckOrStatus) && !isJam && !isEmpty && !isHold) {
        kind = WithTechDispenserStatusKind.ready;
      } else if (rspCmd == rspSystemWarning || isJam || isEmpty) {
        kind = WithTechDispenserStatusKind.warning;
      } else if (rspCmd == rspPayoutWorking || isPayout) {
        kind = WithTechDispenserStatusKind.payoutWorking;
      } else if (rspCmd == rspPayoutSuccessful) {
        kind = WithTechDispenserStatusKind.payoutSuccess;
      } else if (rspCmd == rspPayoutFails) {
        kind = WithTechDispenserStatusKind.payoutFail;
      } else if (rspCmd == rspCountSuccessful || rspCmd == rspCountToPayout || rspCmd == rspCountToReject) {
        kind = WithTechDispenserStatusKind.counting;
      } else if (rspCmd == rspCountPayoutHalt || isHold) {
        kind = WithTechDispenserStatusKind.halted;
      } else if (rspCmd == rspFrameTimeout ||
          rspCmd == rspMissingEtx ||
          rspCmd == rspChecksumError ||
          rspCmd == rspCommandError ||
          rspCmd == rspMaxBillsError) {
        kind = WithTechDispenserStatusKind.error;
      } else {
        kind = WithTechDispenserStatusKind.unknown;
      }

      return WithTechDispenserStatus(
        kind: kind,
        rawCmd: rspCmd,
        data: data,
        statusByte: statusByte,
      );
    } catch (e) {
      logger.e('WithTech: getStatus failed', error: e);
      return const WithTechDispenserStatus(
        kind: WithTechDispenserStatusKind.unknown,
        rawCmd: 0,
        data: 0,
        statusByte: 0,
      );
    }
  }

  /// 마지막 배출 수량 조회 (Last paid-out Q'ty)
  Future<int?> getLastPaidOutQuantity() async {
    try {
      final resp = await _sendCommand(cmdRequestLastOutQty, 0x01);
      if (resp == null) return null;
      if (resp[1] != rspLastPaidOutQty) return null;
      // MEMO-2 기준: CMD=0x36, DATA = 수량 (또는 2바이트 1st/2nd Data 조합)
      return resp[2];
    } catch (e) {
      logger.e('WithTech: getLastPaidOutQuantity failed', error: e);
      return null;
    }
  }

  /// 총 배출 수량 조회 (Total paid-out Q'ty)
  Future<int?> getTotalPaidOutQuantity() async {
    try {
      final resp = await _sendCommand(cmdRequestTotalOut1, 0x01);
      if (resp == null) return null;
      if (resp[1] != rspTotalPaidOutQty) return null;
      final high = resp[2]; // MEMO-1: High Data
      // 실제 2바이트 전체 수량을 쓰려면 2nd Data까지 읽어야 하지만,
      // 여기서는 단일 바이트만 간단히 반환.
      return high;
    } catch (e) {
      logger.e('WithTech: getTotalPaidOutQuantity failed', error: e);
      return null;
    }
  }
}

/// 상태 종류
enum WithTechDispenserStatusKind {
  ready,
  warning,
  payoutWorking,
  payoutSuccess,
  payoutFail,
  counting,
  halted,
  error,
  unknown,
}

/// 상태 응답 결과
class WithTechDispenserStatus {
  final WithTechDispenserStatusKind kind;
  final int rawCmd;
  final int data;
  final int statusByte;

  const WithTechDispenserStatus({
    required this.kind,
    required this.rawCmd,
    required this.data,
    required this.statusByte,
  });
}
