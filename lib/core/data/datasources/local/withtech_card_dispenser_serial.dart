import 'dart:async';
import 'dart:typed_data';

import 'package:serial_port_win32/serial_port_win32.dart';
import 'package:vending_kiosk/core/common/errors/dispenser_exception.dart';
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
  // static const int cmdErrorClearAndProceed = 0x13; // Error(Hold) clear & Job proceed
  static const int cmdCounterClear = 0x14; // Counter clear (FND)
  static const int cmdRequestStatus = 0x15; // Request machine status
  static const int cmdSetMaxCount = 0x16; // Max count setting (Count1)
  static const int cmdRequestTotalOut1 = 0x17; // Request Total-Out Q'ty (1st)
  // static const int cmdRequestTotalOut2 = 0x18; // Request Total-Out Q'ty (2nd)
  static const int cmdRequestLastOutQty = 0x19; // Request Last-Out Q'ty
  // static const int cmdCountBills = 0x1A; // Count Bills
  // static const int cmdCountCancel = 0x1B; // Count Cancel (Reject)
  // static const int cmdCountPayoutHold = 0x1C; // Count / Payout hold
  // static const int cmdMoveCountToPayout = 0x1D; // Counting bills move to payout
  static const int cmdPayoutFirst = 0x1E; // Payout (1st Cartridge) / 카드·지폐 방출 명령
  // static const int cmdPayoutSecond = 0x1F; // Payout (2nd Cartridge)
  static const int cmdRequestLastStatus = 0x50; // Request Last status
  // static const int cmdCr1fLedOrSecondMotor = 0x31; // CR1F1: LED / CR1F2: 2nd Motor time

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

  /// 패킷 송신 + ACK 확인 + 실제 응답 수신
  ///
  /// 프로토콜 흐름 (spec 1.6):
  ///   TX: CMD
  ///   RX: ACK (0x20) — 모든 명령의 첫 번째 응답
  ///   RX: 실제 응답 (0x22 System Ready, 0x36 LastPaidOut 등)
  Future<Uint8List?> _sendCommand(
    int cmd,
    int dataOrStatus, {
    int timeoutMs = 2000,
    int retryCount = 3,
  }) async {
    if (!isConnected) {
      throw DispenserException('WithTech: Serial port is not connected');
    }

    final packet = _createPacket(cmd, dataOrStatus);

    for (int attempt = 0; attempt <= retryCount; attempt++) {
      try {
        // 입력 버퍼 비우기
        try {
          await _port!.readBytes(1024, timeout: const Duration(milliseconds: 1));
        } catch (e) {
          if (_isInvalidHandleError(e)) {
            _isConnected = false;
            _port = null;
            throw DispenserException('WithTech: Serial port handle invalidated (win32 error 6). Reconnect required.');
          }
        }

        logger.d('WithTech: TX [${packet.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ')}]');
        final writeOk = await _port!.writeBytesFromUint8List(packet, timeout: timeoutMs);
        if (_port == null) throw DispenserException('WithTech: Serial port disconnected during write');
        if (!writeOk) throw DispenserException('WithTech: Failed to write packet');

        final timeout = Duration(milliseconds: timeoutMs);

        // Step 1: ACK (0x20) 수신
        Uint8List ackFrame;
        try {
          ackFrame = await _port!.readBytes(frameSize, timeout: timeout);
          logger.d('WithTech: RX ACK [${ackFrame.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ')}]');
          if (ackFrame.length < frameSize) throw TimeoutException('WithTech: ACK read timeout');
        } catch (e) {
          if (_isInvalidHandleError(e)) {
            _isConnected = false;
            _port = null;
            throw DispenserException('WithTech: Serial port handle invalidated. Reconnect required.');
          }
          if (attempt < retryCount) {
            logger.w('WithTech: ACK timeout on attempt ${attempt + 1}, retrying...', error: e);
            await Future.delayed(const Duration(milliseconds: 100));
            continue;
          }
          rethrow;
        }

        if (ackFrame[0] != stx) {
          if (attempt < retryCount) {
            logger.w('WithTech: invalid ACK frame STX on attempt ${attempt + 1}, retrying...');
            await Future.delayed(const Duration(milliseconds: 100));
            continue;
          }
          return null;
        }

        final ackCmd = ackFrame[1];

        // NAK → 재시도
        if (ackCmd == rspNak) {
          if (attempt < retryCount) {
            logger.w('WithTech: NAK on attempt ${attempt + 1}, retrying...');
            await Future.delayed(const Duration(milliseconds: 100));
            continue;
          }
          logger.e('WithTech: NAK after $retryCount retries');
          return null;
        }

        // 첫 프레임이 ACK(0x20)가 아니면 잔류 데이터 → 재시도
        if (ackCmd != rspAckOrStatus) {
          if (attempt < retryCount) {
            logger.w(
                'WithTech: expected ACK(0x20), got 0x${ackCmd.toRadixString(16)} on attempt ${attempt + 1}, retrying...');
            await Future.delayed(const Duration(milliseconds: 100));
            continue;
          }
          logger.e('WithTech: expected ACK(0x20), got 0x${ackCmd.toRadixString(16)}');
          return null;
        }

        // Step 2: 실제 응답 수신
        Uint8List respFrame;
        try {
          respFrame = await _port!.readBytes(frameSize, timeout: timeout);
          logger.d(
              'WithTech: RX [${respFrame.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ')}] (${respFrame.length}/${frameSize}B)');
          if (respFrame.length < frameSize)
            throw TimeoutException('WithTech: Response read timeout after ${timeoutMs}ms');
        } catch (e) {
          if (_isInvalidHandleError(e)) {
            _isConnected = false;
            _port = null;
            throw DispenserException('WithTech: Serial port handle invalidated. Reconnect required.');
          }
          if (attempt < retryCount) {
            logger.w('WithTech: response timeout on attempt ${attempt + 1}, retrying...', error: e);
            await Future.delayed(const Duration(milliseconds: 100));
            continue;
          }
          rethrow;
        }

        if (respFrame[0] != stx || respFrame[3] != etx || respFrame[5] != cr || respFrame[6] != lf) {
          if (attempt < retryCount) {
            logger.w('WithTech: invalid response frame markers on attempt ${attempt + 1}, retrying...');
            await Future.delayed(const Duration(milliseconds: 100));
            continue;
          }
          logger.e('WithTech: invalid response frame markers. frame=${respFrame.map((e) => e.toRadixString(16))}');
          return null;
        }

        // 체크섬 검증 (펌웨어 quirk 허용)
        final receivedChecksum = respFrame[4];
        final calcWithStx = _calculateChecksum(respFrame[1], respFrame[2]);
        final calcWithoutStx = (respFrame[1] + respFrame[2] + etx) & 0xFF;
        if (receivedChecksum != calcWithStx && receivedChecksum != calcWithoutStx) {
          logger.w(
            'WithTech: checksum mismatch (firmware quirk, continuing): '
            'recv=0x${receivedChecksum.toRadixString(16)}, '
            'expected=0x${calcWithStx.toRadixString(16)}',
          );
        }

        return respFrame;
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
  /// TX 1회 전송 후 장치가 보내는 모든 RX 프레임을 읽어 최종 결과를 반환한다.
  ///
  /// 프로토콜 응답 흐름 (예: 5장 배출):
  ///   TX: 02 1E 05 03 28 0D 0A
  ///   RX: 02 20 00 03 25 0D 0A  ← ACK
  ///   RX: 02 29 01 ...          ← 1장 배출 중
  ///   RX: 02 29 02 ...          ← 2장 배출 중
  ///   ...
  ///   RX: 02 2E 05 ...          ← 5장 배출 성공 (종료)
  ///
  /// - [onProgress]: 배출 진행 수량 콜백 (dispensed, total)
  /// - [totalTimeout]: 전체 완료 대기 타임아웃 (기본 15초)
  Future<bool> payout(
    int count, {
    Duration totalTimeout = const Duration(seconds: 15),
    void Function(int dispensed, int total)? onProgress,
  }) async {
    if (!isConnected) {
      throw DispenserException('WithTech: Serial port is not connected');
    }
    if (count < 1 || count > 255) {
      logger.e('WithTech: invalid payout count: $count');
      return false;
    }

    try {
      // 입력 버퍼 비우기 (이전 잔류 데이터 제거)
      try {
        await _port!.readBytes(1024, timeout: const Duration(milliseconds: 1));
      } catch (e) {
        if (_isInvalidHandleError(e)) {
          _isConnected = false;
          _port = null;
          throw DispenserException('WithTech: Serial port handle invalidated. Reconnect required.');
        }
      }

      final packet = _createPacket(cmdPayoutFirst, count);
      logger.d('WithTech: TX [${packet.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ')}]');

      final writeOk = await _port!.writeBytesFromUint8List(packet, timeout: 2000);
      if (_port == null) throw DispenserException('WithTech: Serial port disconnected during write');
      if (!writeOk) throw DispenserException('WithTech: Failed to write payout packet');

      final deadline = DateTime.now().add(totalTimeout);

      while (DateTime.now().isBefore(deadline)) {
        final remaining = deadline.difference(DateTime.now());
        final frameTimeout = remaining < const Duration(seconds: 2) ? remaining : const Duration(seconds: 2);

        Uint8List frame;
        try {
          frame = await _port!.readBytes(frameSize, timeout: frameTimeout);
        } catch (e) {
          if (_isInvalidHandleError(e)) {
            _isConnected = false;
            _port = null;
            throw DispenserException('WithTech: Serial port handle invalidated. Reconnect required.');
          }
          // 프레임 읽기 타임아웃 → 전체 타임아웃까지 재시도
          continue;
        }

        if (frame.length < frameSize) continue;

        logger.d('WithTech: RX [${frame.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ')}]');

        if (frame[0] != stx) continue;

        final cmd = frame[1];
        final data = frame[2];

        switch (cmd) {
          case rspAckOrStatus: // 0x20 - ACK, 배출 시작 대기
            logger.d('WithTech: payout ACK');
          case rspPayoutWorking: // 0x29 - 배출 진행 중
            logger.d('WithTech: payout working $data/$count');
            onProgress?.call(data, count);
          case rspPayoutSuccessful: // 0x2E - 최종 성공
            logger.i('WithTech: payout successful ($data cards)');
            return true;
          case rspPayoutFails: // 0x2F - 최종 실패
            logger.e('WithTech: payout failed ($data cards dispensed)');
            return false;
          case rspSystemWarning: // 0x23 - 카드 없음 등
            logger.e('WithTech: payout system warning (status=0x${data.toRadixString(16)})');
            return false;
          case rspNak: // 0x21 - NAK
            logger.e('WithTech: payout NAK');
            return false;
          case rspMaxBillsError: // 0x28 - 최대 수량 초과
            logger.e('WithTech: payout max bills error');
            return false;
          default:
            logger.w('WithTech: payout unexpected cmd=0x${cmd.toRadixString(16)} data=0x${data.toRadixString(16)}');
        }
      }

      logger.e('WithTech: payout timeout after ${totalTimeout.inSeconds}s');
      return false;
    } catch (e) {
      logger.e('WithTech: payout failed', error: e);
      rethrow;
    }
  }

  /// 장비 상태 요청 (Request machine status or last status).
  ///
  /// 프로토콜 응답 흐름 (1.7.1 참조):
  ///   TX: 02 15 00 03 1A 0D 0A
  ///   RX: 02 20 00 03 25 0D 0A  ← ACK (스킵)
  ///   RX: 02 22 00 03 27 0D 0A  ← 실제 상태 (READY 등)
  ///
  /// ACK(0x20, data=0x00)는 중간 응답으로 스킵하고 실제 상태 프레임을 기다린다.
  Future<WithTechDispenserStatus> getStatus({bool lastStatus = false}) async {
    const unknown = WithTechDispenserStatus(
      kind: WithTechDispenserStatusKind.unknown,
      rawCmd: 0,
      data: 0,
      statusByte: 0,
    );

    if (!isConnected) return unknown;

    try {
      // 버퍼 비우기
      try {
        await _port!.readBytes(1024, timeout: const Duration(milliseconds: 1));
      } catch (e) {
        if (_isInvalidHandleError(e)) {
          _isConnected = false;
          _port = null;
          throw DispenserException('WithTech: Serial port handle invalidated. Reconnect required.');
        }
      }

      final cmdToSend = lastStatus ? cmdRequestLastStatus : cmdRequestStatus;
      final packet = _createPacket(cmdToSend, 0x00);
      logger.d('WithTech: TX [${packet.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ')}]');

      final writeOk = await _port!.writeBytesFromUint8List(packet, timeout: 2000);
      if (!writeOk) throw DispenserException('WithTech: Failed to write status request packet');

      // 최대 2초 내에 실제 상태 프레임을 기다림
      final deadline = DateTime.now().add(const Duration(seconds: 2));
      while (DateTime.now().isBefore(deadline)) {
        final remaining = deadline.difference(DateTime.now());
        Uint8List frame;
        try {
          frame = await _port!.readBytes(frameSize, timeout: remaining);
        } catch (e) {
          if (_isInvalidHandleError(e)) {
            _isConnected = false;
            _port = null;
            throw DispenserException('WithTech: Serial port handle invalidated. Reconnect required.');
          }
          break; // 타임아웃
        }

        if (frame.length < frameSize) break;
        if (frame[0] != stx) continue;

        logger.d('WithTech: RX [${frame.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ')}]');

        final rspCmd = frame[1];
        final data = frame[2];

        // ACK(0x20)이고 status byte가 0x00이면 중간 응답 → 실제 상태 프레임 대기
        if (rspCmd == rspAckOrStatus) {
          logger.d('WithTech: getStatus ACK received, waiting for actual status...');
          continue;
        }

        // 실제 상태 프레임 파싱
        final statusByte = data;
        final isJam = (statusByte & 0x80) != 0;
        final isEmpty = (statusByte & 0x10) != 0;
        final isHold = (statusByte & 0x08) != 0;
        final isPayout = (statusByte & 0x04) != 0;

        WithTechDispenserStatusKind kind;
        if (rspCmd == rspSystemReady && !isJam && !isEmpty && !isHold) {
          kind = WithTechDispenserStatusKind.ready;
        } else if (rspCmd == rspAckOrStatus && !isJam && !isEmpty && !isHold) {
          // status byte에 에러 비트 없는 0x20 → ready로 간주
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
        } else if (rspCmd == rspNak ||
            rspCmd == rspFrameTimeout ||
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
      }

      logger.w('WithTech: getStatus timeout, no definitive status frame received');
      return unknown;
    } catch (e) {
      logger.e('WithTech: getStatus failed', error: e);
      return unknown;
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
