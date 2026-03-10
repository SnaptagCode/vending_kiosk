import 'dart:async';
import 'dart:typed_data';
import 'package:vending_kiosk/core/common/logger/logger_service.dart';
import 'package:vending_kiosk/core/data/datasources/local/card_dispenser_protocol.dart';
import 'package:serial_port_win32/serial_port_win32.dart';

/// 카드 배출기 시리얼 통신 클래스
/// ONEPLUS Card Dispenser RS-232 통신 사양서 기반
///
/// - **포트 설정**: 9600bps, 8 data bits, 1 stop bit, no parity
/// - **패킷**: `'$'(0x24)` + `Command(1)` + `Data(2)` + `Checksum(1)`
/// - **Checksum**: (unsigned char)(Command + Data1 + Data2)
/// - **DIP SW3**:
///   - OFF: TX는 대문자 ASCII, RX는 소문자 ASCII (기존)
///   - ON : TX는 소문자 ASCII, RX는 소문자 ASCII (신규, 일부 command 제외)
class CardDispenserSerial {
  /// DIP SW3에 따른 프로토콜
  final CardDispenserProtocol protocol;

  // 통신 설정
  static const int baudRate = 9600;
  static const int dataBits = 8;
  static const int stopBits = 1;
  static const String parity = 'none';

  // 패킷 구성
  static const int packetSize = 5;
  static const int stxByte = 0x24; // '$' ASCII

  // 명령어 정의 (DIP SW 3번 OFF 기준 - 대문자 TX, 소문자 RX)
  static const int cmdHealthCheck = 0x48; // 'H'
  static const int cmdReset = 0x49; // 'I'
  static const int cmdDispense = 0x44; // 'D'

  static const int cmdDisable = 0x48; // 'H' (동작 금지)
  static const int cmdEnable = 0x48; // 'H' (동작 금지 해제)
  static const int cmdStatus = 0x53; // 'S'
  static const int cmdError = 0x53; // 'S' (에러 확인)

  // 상태 응답 코드
  static const int statusStandby = 0x73; // 's' + 't' + 'b' (대기 상태)
  static const int statusDispensing = 0x73; // 's' + 'o' + 'n' (배출 동작 중)
  static const int statusDisabled = 0x73; // 's' + 'h' + '!' (동작 금지)

  // 에러 코드
  static const int errorEmpty = 0x81; // 카드 부족
  static const int errorJam = 0x82; // 카드 걸림
  static const int errorDouble = 0x83; // 카드 겹침
  static const int errorNotEmit = 0x84; // 카드 미방출
  static const int errorLengthLong = 0x85; // 카드 길이 불량 (긴 것)
  static const int errorLengthShort = 0x86; // 카드 길이 불량 (짧은 것)
  static const int errorSensor = 0x87; // 센서 불량
  static const int errorSetting = 0x8a; // 셋팅 값 불량
  static const int errorMotor = 0x8c; // 모터 불량
  static const int errorLengthDifferential = 0x8e; // 카드 틀어짐

  String? _portName;
  SerialPort? _port;
  bool _isConnected = false;

  CardDispenserSerial({
    String? portName,
    this.protocol = CardDispenserProtocol.txUpperRxLower,
  }) : _portName = portName;

  String? get portName => _portName;

  int _toTxAscii(int byte) {
    if (protocol != CardDispenserProtocol.txLowerRxLower) return byte;
    // ASCII uppercase A-Z -> lowercase a-z
    if (byte >= 0x41 && byte <= 0x5A) return byte + 0x20;
    return byte;
  }

  bool _isAsciiEitherCase(int actual, int upper) {
    final lower = (upper >= 0x41 && upper <= 0x5A) ? upper + 0x20 : upper;
    return actual == upper || actual == lower;
  }

  /// Win32 error 6 (ERROR_INVALID_HANDLE) 여부 확인
  static bool _isInvalidHandleError(Object e) {
    return e.toString().contains('win32 error code is 6');
  }

  /// Win32 오류 코드에 따른 안내 문구 (접근 거부 등)
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
            '앱을 강제 종료한 경우: 장치 관리자 → [포트(COM & LPT)] 또는 [범용 직렬 버스 컨트롤러]에서 '
            '해당 장치 우클릭 → [제거] → 상단 [동작] → [하드웨어 변경 사항 검사] (PC 재시작 불필요).';
      case 32:
        return 'Error 32 (공유 위반): COM 포트가 사용 중입니다. '
            '앱 강제 종료 후: 장치 관리자에서 해당 COM 장치 [제거] → [동작] → [하드웨어 변경 사항 검사] (PC 재시작 불필요).';
      default:
        return 'Win32 error $code. Try closing other apps using this port or run as Administrator.';
    }
  }

  /// 사용 가능한 시리얼 포트 목록 조회
  static List<String> getAvailablePorts() {
    try {
      return SerialPort.getAvailablePorts();
    } catch (e) {
      logger.e('Failed to get available ports', error: e);
      return [];
    }
  }

  /// 리소스 정리
  void dispose() {
    disconnect();
  }

  /// 시리얼 포트 연결
  /// [portName] 예: 'COM1', 'COM3' (Windows)
  /// 앱 재실행 시 포트가 아직 해제되지 않았을 수 있어, error 0/5 시 재시도합니다.
  Future<bool> connect(String portName) async {
    final didConnect = await _connectOnce(portName);
    if (didConnect) return true;

    final lastError = _lastConnectError;
    final errorMsg = lastError?.toString() ?? '';
    final isError0 = errorMsg.contains('win32 error code is 0');
    final isError5 = errorMsg.contains('win32 error code is 5');

    // Error 0 또는 5일 때 재시도 (포트가 해제 중이거나 다른 프로세스가 막 종료한 경우)
    if (isError0 || isError5) {
      final retryMsg = isError0 ? '포트 해제 대기 중' : '포트 액세스 재시도 중 (앱 재시작 직후 또는 이전 연결이 완전히 닫히지 않았을 수 있음)';
      logger.w('Card dispenser: $retryMsg - 2초 후 재시도...');
      await Future<void>.delayed(const Duration(seconds: 2));

      final secondAttempt = await _connectOnce(portName);
      if (secondAttempt) return true;

      // Error 5가 계속되면 추가로 한 번 더 시도 (총 3회)
      if (isError5) {
        logger.w('Card dispenser: 2차 재시도 (3초 대기 후)...');
        await Future<void>.delayed(const Duration(seconds: 3));
        final thirdAttempt = await _connectOnce(portName);
        if (thirdAttempt) return true;

        // 마지막 시도 (총 4회)
        logger.w('Card dispenser: 최종 재시도 (5초 대기 후)...');
        await Future<void>.delayed(const Duration(seconds: 5));
        return await _connectOnce(portName);
      }
    }

    return false;
  }

  Object? _lastConnectError;

  Future<bool> _connectOnce(String portName) async {
    _lastConnectError = null;
    try {
      // 기존 연결이 있으면 완전히 정리
      if (_isConnected && _port != null) {
        await disconnect();
      }

      // 기존 인스턴스가 남아있으면 명시적으로 제거 (재시도 시 완전히 새로 생성)
      if (_port != null) {
        try {
          if (_port!.isOpened) {
            _port!.close();
          }
        } catch (e) {
          logger.w('Failed to close previous port instance during cleanup', error: e);
        }
        _port = null;
        // 포트 리소스가 완전히 해제될 때까지 대기
        await Future<void>.delayed(const Duration(milliseconds: 300));
      }

      _portName = portName;

      // 완전히 새로운 SerialPort 인스턴스 생성
      _port = SerialPort(
        portName,
        openNow: false,
        ByteSize: dataBits,
        BaudRate: baudRate,
        StopBits: 0,
        Parity: 0,
      );

      await _port!.open();

      if (_port!.isOpened) {
        _isConnected = true;
        logger.i('CardDispenserSerial Card dispenser connected to $portName (protocol: $protocol)');
        return true;
      } else {
        logger.e('CardDispenserSerialFailed to open serial port $portName');
        _port = null;
        return false;
      }
    } catch (e) {
      _lastConnectError = e;
      final available = getAvailablePorts();
      final hint = _win32ErrorHint(e);
      logger.e(
        'Failed to connect to card dispenser at $portName. '
        'Available ports: $available. $hint',
        error: e,
      );
      _isConnected = false;
      _port = null;
      return false;
    }
  }

  /// 시리얼 포트 연결 해제
  Future<void> disconnect() async {
    try {
      if (_port != null && _port!.isOpened) {
        _port!.close();
        logger.d('Card dispenser port closed');
      }
      _isConnected = false;
      _port = null;
      logger.i('Card dispenser disconnected (${_portName ?? '-'})');
    } catch (e) {
      logger.e('Failed to disconnect card dispenser', error: e);
      _isConnected = false;
      _port = null;
    }
  }

  /// 연결 상태 확인
  bool get isConnected => _isConnected && _port != null && _port!.isOpened;

  /// Checksum 계산
  /// Checksum = (unsigned char)(Command + Data1 + Data2)
  int _calculateChecksum(int cmd, int data1, int data2) {
    return (cmd + data1 + data2) & 0xFF;
  }

  /// 패킷 생성
  /// 형식: "$" + Command + Data1 + Data2 + Checksum
  Uint8List _createPacket(int cmd, int data1, int data2) {
    final txCmd = _toTxAscii(cmd);
    final txData1 = _toTxAscii(data1);
    final txData2 = _toTxAscii(data2);
    final checksum = _calculateChecksum(txCmd, txData1, txData2);
    return Uint8List.fromList([
      stxByte,
      txCmd,
      txData1,
      txData2,
      checksum,
    ]);
  }

  /// 패킷 전송 및 응답 수신
  ///
  /// [timeoutMs] 응답 대기 시간 (밀리초), 기본 500ms
  /// [retryCount] 재시도 횟수, 기본 5회
  Future<Uint8List?> _sendCommand(
    int cmd,
    int data1,
    int data2, {
    int timeoutMs = 500,
    int retryCount = 5,
  }) async {
    if (!isConnected) {
      logger.e('Serial port is not connected');
      throw Exception('Serial port is not connected');
    }

    final packet = _createPacket(cmd, data1, data2);

    for (int attempt = 0; attempt <= retryCount; attempt++) {
      try {
        // 입력 버퍼 비우기 (이전 데이터 제거)
        // timeout을 1ms로 최소화: readBytes는 내부적으로 Timer.periodic을 사용하므로
        // 긴 timeout은 불필요한 타이머 콜백을 대량 생성해 UI 스레드를 포화시킴.
        try {
          _port!.readBytes(1000, timeout: const Duration(milliseconds: 1));
        } catch (e) {
          // 버퍼가 비어있으면 무시 (error 6: 핸들 무효화 포함)
          if (_isInvalidHandleError(e)) {
            _isConnected = false;
            _port = null;
            throw Exception('Serial port handle invalidated (win32 error 6). Reconnect required.');
          }
        }

        // 패킷 전송
        final writeSuccess = await _port!.writeBytesFromUint8List(packet, timeout: timeoutMs);
        if (!writeSuccess) {
          throw Exception('Failed to write packet');
        }
        // 패킷 로그: 디버그 콘솔 과부하 방지를 위해 제거 (autoDetect 중 대량 출력됨)

        // 응답 수신 대기
        final timeout = Duration(milliseconds: timeoutMs);
        Uint8List? response;

        try {
          // readBytes(timeout:)는 내부적으로 Timer.periodic을 사용하여 타임아웃 시
          // timer.cancel()을 호출해 이벤트 루프를 막는 orphaned 타이머가 생기지 않음.
          // readFixedSizeBytes().timeout()은 타임아웃 후에도 Future.delayed 루프가
          // 계속 남아 UI 스레드를 점령하는 문제가 있어 사용하지 않음.
          response = await _port!.readBytes(packetSize, timeout: timeout);
          if (response.length < packetSize) {
            throw TimeoutException('Read timeout after ${timeoutMs}ms');
          }
        } catch (e) {
          // 핸들 무효화 시 즉시 연결 해제 처리 후 재시도 불필요
          if (_isInvalidHandleError(e)) {
            _isConnected = false;
            _port = null;
            throw Exception('Serial port handle invalidated (win32 error 6). Reconnect required.');
          }
          // 타임아웃 또는 읽기 실패
          if (attempt < retryCount) {
            logger.w('Response timeout on attempt ${attempt + 1}, retrying...', error: e);
            await Future.delayed(Duration(milliseconds: 100));
            continue;
          } else {
            logger.e('Failed to read response after $retryCount attempts', error: e);
            rethrow;
          }
        }

        if (response.length != packetSize) {
          if (attempt < retryCount) {
            logger.w('Invalid response length: ${response.length}, expected $packetSize. Retrying...');
            await Future.delayed(Duration(milliseconds: 100));
            continue;
          } else {
            logger.e('Invalid response length: ${response.length}, expected $packetSize');
            return null;
          }
        }

        // STX 확인
        if (response[0] != stxByte) {
          if (attempt < retryCount) {
            logger.w(
                'Invalid STX byte: 0x${response[0].toRadixString(16)}, expected 0x${stxByte.toRadixString(16)}. Retrying...');
            await Future.delayed(Duration(milliseconds: 100));
            continue;
          } else {
            logger.e('Invalid STX byte: 0x${response[0].toRadixString(16)}, expected 0x${stxByte.toRadixString(16)}');
            return null;
          }
        }

        // Checksum 검증
        final receivedChecksum = response[4];
        final calculatedChecksum = _calculateChecksum(
          response[1],
          response[2],
          response[3],
        );

        if (receivedChecksum != calculatedChecksum) {
          if (attempt < retryCount) {
            logger.w(
                'Checksum mismatch: received 0x${receivedChecksum.toRadixString(16)}, calculated 0x${calculatedChecksum.toRadixString(16)}. Retrying...');
            await Future.delayed(Duration(milliseconds: 100));
            continue;
          } else {
            logger.e(
                'Checksum mismatch: received 0x${receivedChecksum.toRadixString(16)}, calculated 0x${calculatedChecksum.toRadixString(16)}');
            return null;
          }
        }

        // 정상 응답 반환
        return response;
      } catch (e) {
        // 핸들 무효화는 재시도해도 의미 없으므로 즉시 rethrow
        if (_isInvalidHandleError(e)) rethrow;
        if (attempt < retryCount) {
          logger.w('Command send attempt ${attempt + 1} failed, retrying...', error: e);
          await Future.delayed(Duration(milliseconds: 100));
        } else {
          logger.e('Command send failed after $retryCount retries', error: e);
          rethrow;
        }
      }
    }

    return null;
  }

  /// 통신 확인 (Health Check)
  ///
  /// 명령: "$" + "H" + "I" + "?"
  /// 응답: "$" + "m" + "e" + "!" (정상) 또는 "$" + "M" + "E" + "!" (DIP SW 3번 ON)
  Future<bool> healthCheck({int timeoutMs = 500, int retryCount = 5}) async {
    try {
      // '?' = 0x3F
      final response = await _sendCommand(cmdHealthCheck, 0x49, 0x3F, timeoutMs: timeoutMs, retryCount: retryCount);
      if (response != null) {
        // 응답 확인: "m" + "e" + "!" 또는 "M" + "E" + "!"
        final isValid = (response[1] == 0x6D && response[2] == 0x65 && response[3] == 0x21) ||
            (response[1] == 0x4D && response[2] == 0x45 && response[3] == 0x21);
        return isValid;
      }
      return false;
    } catch (e) {
      logger.e('Health check failed', error: e);
      return false;
    }
  }

  /// 단일 연결 시도 (재시도 없음) — autoDetect 전용
  Future<bool> connectOnce(String portName) => _connectOnce(portName);

  /// 사용 가능한 포트 중 카드 배출기를 자동 감지합니다.
  ///
  /// 모든 COM 포트를 순회하며 Health Check에 응답하는 포트를 반환합니다.
  /// 이미 다른 프로세스가 점유한 포트는 Error 5로 자동 스킵됩니다.
  static Future<({String port, CardDispenserProtocol protocol})?> autoDetect({
    List<CardDispenserProtocol>? protocols,
    int connectTimeoutMs = 1000,
    // 200ms: 500ms 대비 readBytes Timer.periodic 콜백 수를 60% 줄여 UI 스레드 부하 완화
    int healthCheckTimeoutMs = 200,
  }) async {
    final ports = getAvailablePorts();
    if (ports.isEmpty) {
      logger.w('CardDispenserSerial.autoDetect: 사용 가능한 COM 포트 없음');
      return null;
    }

    logger.i('CardDispenserSerial.autoDetect: 스캔 시작 → 포트: $ports');
    final tryProtocols = protocols ?? CardDispenserProtocol.values;

    for (final port in ports) {
      for (final protocol in tryProtocols) {
        final dispenser = CardDispenserSerial(protocol: protocol);
        try {
          bool connected = false;
          try {
            connected = await dispenser
                .connectOnce(port)
                .timeout(Duration(milliseconds: connectTimeoutMs), onTimeout: () => false);
          } catch (_) {
            connected = false;
          }

          if (!connected) continue;

          final healthy = await dispenser.healthCheck(
            timeoutMs: healthCheckTimeoutMs,
            retryCount: 0,
          );

          if (healthy) {
            logger.i('CardDispenserSerial.autoDetect: 배출기 감지 성공 → $port ($protocol)');
            return (port: port, protocol: protocol);
          }
        } catch (e) {
          logger.d('CardDispenserSerial.autoDetect: $port ($protocol) 응답 없음 - $e');
        } finally {
          try {
            await dispenser.disconnect();
          } catch (_) {}
        }
      }
    }

    logger.w('CardDispenserSerial.autoDetect: 모든 포트 스캔 완료 - 배출기 감지 실패. 포트: $ports');
    return null;
  }

  /// 초기화 (Reset)
  ///
  /// 명령: "$" + "I" + 0x00 + 0x00
  /// 응답(정상): "$" + "i" + 0x00 + "a"
  /// 응답(불능): "$" + "n" + "s" + "!"
  Future<bool> reset() async {
    try {
      final response = await _sendCommand(cmdReset, 0x00, 0x00);
      if (response != null) {
        // 정상 응답: (i/I) + 0x00 + (a/A)
        final ok = _isAsciiEitherCase(response[1], 0x49) /* I */ &&
            response[2] == 0x00 &&
            _isAsciiEitherCase(response[3], 0x41) /* A */;
        if (ok) return true;

        // 불능 응답: (n/N) + (s/S) + '!'
        final ns = _isAsciiEitherCase(response[1], 0x4E) /* N */ &&
            _isAsciiEitherCase(response[2], 0x53) /* S */ &&
            response[3] == 0x21;
        if (ns) return false;

        return false;
      }
      return false;
    } catch (e) {
      logger.e('Reset failed', error: e);
      return false;
    }
  }

  /// 카드 배출
  ///
  /// [count] 배출할 카드 수 (1-255)
  /// 명령: "$" + "D" + (카드수) + "S"
  /// 응답: "$" + "d" + (카드수) + "a" (정상) 또는 "$" + "n" + "s" + "!" (불능)
  Future<bool> dispenseCard(int count) async {
    if (count < 1 || count > 255) {
      logger.e('Invalid card count: $count (must be 1-255)');
      return false;
    }

    try {
      // 'S' = 0x53
      final response = await _sendCommand(cmdDispense, count, 0x53);
      if (response != null) {
        // 정상 응답: "d" + (카드수) + "a" 또는 "D" + (카드수) + "A"
        final isSuccess = (response[1] == 0x64 && response[2] == count && response[3] == 0x61) ||
            (response[1] == 0x44 && response[2] == count && response[3] == 0x41);
        return isSuccess;
      }
      return false;
    } catch (e) {
      logger.e('Dispense card failed', error: e);
      return false;
    }
  }

  /// 상태 확인
  ///
  /// 명령: "$" + "S" + 0x00 + 0x00
  /// 응답:
  /// - "$" + "s" + "t" + "b" : 대기 상태
  /// - "$" + "s" + "o" + "n" : 배출 동작 중
  /// - "$" + "s" + "h" + "!" : 동작 금지 상태
  /// - "$" + "s" + (카드수) + "o" : (카드수)장 배출 후 정상 종료
  /// - "$" + "s" + (카드수) + "n" : (카드수)장 배출 후 비정상 종료
  Future<CardDispenserStatus> getStatus() async {
    try {
      final response = await _sendCommand(cmdStatus, 0x00, 0x00);
      if (response != null && response.length >= 4) {
        return _parseStatusResponse(response);
      }
      return const CardDispenserStatus.unknown();
    } catch (e) {
      logger.e('Get status failed', error: e);
      return const CardDispenserStatus.unknown();
    }
  }

  /// 상태 응답 파싱
  CardDispenserStatus _parseStatusResponse(Uint8List response) {
    final byte1 = response[1];
    final byte2 = response[2];
    final byte3 = response[3];

    // 대기 상태: "s" + "t" + "b" 또는 "S" + "T" + "B"
    if ((byte1 == 0x73 && byte2 == 0x74 && byte3 == 0x62) || (byte1 == 0x53 && byte2 == 0x54 && byte3 == 0x42)) {
      return const CardDispenserStatus.standby();
    }

    // 배출 동작 중: "s" + "o" + "n" 또는 "S" + "O" + "N"
    if ((byte1 == 0x73 && byte2 == 0x6F && byte3 == 0x6E) || (byte1 == 0x53 && byte2 == 0x4F && byte3 == 0x4E)) {
      return const CardDispenserStatus.dispensing();
    }

    // 동작 금지: "s" + "h" + "!" 또는 "S" + "H" + "!"
    if ((byte1 == 0x73 && byte2 == 0x68 && byte3 == 0x21) || (byte1 == 0x53 && byte2 == 0x48 && byte3 == 0x21)) {
      return const CardDispenserStatus.disabled();
    }

    // 배출 완료 (정상): "s" + (카드수) + "o" 또는 "S" + (카드수) + "O"
    if ((byte1 == 0x73 && byte3 == 0x6F) || (byte1 == 0x53 && byte3 == 0x4F)) {
      return CardDispenserStatus.completed(byte2);
    }

    // 배출 완료 (비정상): "s" + (카드수) + "n" 또는 "S" + (카드수) + "N"
    if ((byte1 == 0x73 && byte3 == 0x6E) || (byte1 == 0x53 && byte3 == 0x4E)) {
      return CardDispenserStatus.error(byte2);
    }

    return const CardDispenserStatus.unknown();
  }

  /// 에러 코드 확인
  ///
  /// 명령: "$" + "S" + "E" + "R"
  /// 응답: "$" + "s" + "e" + (에러코드)
  Future<CardDispenserError?> getError() async {
    try {
      // 'E' = 0x45, 'R' = 0x52
      final response = await _sendCommand(cmdError, 0x45, 0x52);
      if (response != null && response.length >= 4) {
        // 응답 형식: "s" + "e" + (에러코드)
        if ((response[1] == 0x73 && response[2] == 0x65) || (response[1] == 0x53 && response[2] == 0x45)) {
          final errorCode = response[3];
          return _parseErrorCode(errorCode);
        }
      }
      return null;
    } catch (e) {
      logger.e('Get error failed', error: e);
      return null;
    }
  }

  /// 에러 코드 파싱
  CardDispenserError? _parseErrorCode(int errorCode) {
    switch (errorCode) {
      case errorEmpty:
        return CardDispenserError.empty;
      case errorJam:
        return CardDispenserError.jam;
      case errorDouble:
        return CardDispenserError.double;
      case errorNotEmit:
        return CardDispenserError.notEmit;
      case errorLengthLong:
        return CardDispenserError.lengthLong;
      case errorLengthShort:
        return CardDispenserError.lengthShort;
      case errorSensor:
        return CardDispenserError.sensor;
      case errorSetting:
        return CardDispenserError.setting;
      case errorMotor:
        return CardDispenserError.motor;
      case errorLengthDifferential:
        return CardDispenserError.lengthDifferential;
      default:
        return null;
    }
  }

  /// 동작 금지 설정
  ///
  /// 명령: "$" + "H" + 0x00 + 0x00
  Future<bool> disable() async {
    try {
      final response = await _sendCommand(cmdDisable, 0x00, 0x00);
      if (response != null) {
        // 정상 응답: (h/H) + 0x00 + (a/A)
        final isSuccess = _isAsciiEitherCase(response[1], 0x48) /* H */ &&
            response[2] == 0x00 &&
            _isAsciiEitherCase(response[3], 0x41) /* A */;
        return isSuccess;
      }
      return false;
    } catch (e) {
      logger.e('Disable failed', error: e);
      return false;
    }
  }

  /// 동작 금지 해제
  ///
  /// 명령: "$" + "H" + "C" + "?"
  Future<bool> enable() async {
    try {
      // 'C' = 0x43, '?' = 0x3F
      final response = await _sendCommand(cmdEnable, 0x43, 0x3F);
      if (response != null) {
        // 정상 응답: "h" + "c" + "!" 또는 "H" + "C" + "!"
        final isSuccess = (response[1] == 0x68 && response[2] == 0x63 && response[3] == 0x21) ||
            (response[1] == 0x48 && response[2] == 0x43 && response[3] == 0x21);
        return isSuccess;
      }
      return false;
    } catch (e) {
      logger.e('Enable failed', error: e);
      return false;
    }
  }
}

/// 카드 배출기 상태
sealed class CardDispenserStatus {
  const CardDispenserStatus();

  const factory CardDispenserStatus.standby() = _StandbyStatus;
  const factory CardDispenserStatus.dispensing() = _DispensingStatus;
  const factory CardDispenserStatus.disabled() = _DisabledStatus;
  const factory CardDispenserStatus.completed(int count) = _CompletedStatus;
  const factory CardDispenserStatus.error(int count) = _ErrorStatus;
  const factory CardDispenserStatus.unknown() = _UnknownStatus;
}

enum CardDispenserStatusKind {
  standby,
  dispensing,
  disabled,
  completed,
  error,
  unknown,
}

extension CardDispenserStatusX on CardDispenserStatus {
  CardDispenserStatusKind get kind {
    switch (this) {
      case _StandbyStatus():
        return CardDispenserStatusKind.standby;
      case _DispensingStatus():
        return CardDispenserStatusKind.dispensing;
      case _DisabledStatus():
        return CardDispenserStatusKind.disabled;
      case _CompletedStatus():
        return CardDispenserStatusKind.completed;
      case _ErrorStatus():
        return CardDispenserStatusKind.error;
      case _UnknownStatus():
        return CardDispenserStatusKind.unknown;
    }
  }

  int? get count {
    switch (this) {
      case _CompletedStatus(:final count):
        return count;
      case _ErrorStatus(:final count):
        return count;
      default:
        return null;
    }
  }
}

class _StandbyStatus extends CardDispenserStatus {
  const _StandbyStatus();
}

class _DispensingStatus extends CardDispenserStatus {
  const _DispensingStatus();
}

class _DisabledStatus extends CardDispenserStatus {
  const _DisabledStatus();
}

class _CompletedStatus extends CardDispenserStatus {
  final int count;
  const _CompletedStatus(this.count);
}

class _ErrorStatus extends CardDispenserStatus {
  final int count;
  const _ErrorStatus(this.count);
}

class _UnknownStatus extends CardDispenserStatus {
  const _UnknownStatus();
}

/// 카드 배출기 에러 코드
enum CardDispenserError {
  empty, // 0x81 - 카드 부족
  jam, // 0x82 - 카드 걸림
  double, // 0x83 - 카드 겹침
  notEmit, // 0x84 - 카드 미방출
  lengthLong, // 0x85 - 카드 길이 불량 (긴 것)
  lengthShort, // 0x86 - 카드 길이 불량 (짧은 것)
  sensor, // 0x87 - 센서 불량
  setting, // 0x8a - 셋팅 값 불량
  motor, // 0x8c - 모터 불량
  lengthDifferential, // 0x8e - 카드 틀어짐
}

extension CardDispenserErrorExtension on CardDispenserError {
  String get description {
    switch (this) {
      case CardDispenserError.empty:
        return '카드 부족';
      case CardDispenserError.jam:
        return '카드 걸림';
      case CardDispenserError.double:
        return '카드 겹침';
      case CardDispenserError.notEmit:
        return '카드 미방출';
      case CardDispenserError.lengthLong:
        return '카드 길이 불량 (긴 것)';
      case CardDispenserError.lengthShort:
        return '카드 길이 불량 (짧은 것)';
      case CardDispenserError.sensor:
        return '센서 불량';
      case CardDispenserError.setting:
        return '셋팅 값 불량';
      case CardDispenserError.motor:
        return '모터 불량';
      case CardDispenserError.lengthDifferential:
        return '카드 틀어짐';
    }
  }

  String get errorCode {
    switch (this) {
      case CardDispenserError.empty:
        return 'Er-1';
      case CardDispenserError.jam:
        return 'Er-2';
      case CardDispenserError.double:
        return 'Er-3';
      case CardDispenserError.notEmit:
        return 'Er-4';
      case CardDispenserError.lengthLong:
        return 'Er-5';
      case CardDispenserError.lengthShort:
        return 'Er-6';
      case CardDispenserError.sensor:
        return 'Er-12';
      case CardDispenserError.setting:
        return 'Er-10';
      case CardDispenserError.motor:
        return 'Er-12';
      case CardDispenserError.lengthDifferential:
        return 'Er-14';
    }
  }
}
