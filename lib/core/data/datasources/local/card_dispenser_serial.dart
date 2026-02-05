import 'dart:async';
import 'dart:typed_data';
import 'package:vending_kiosk/core/common/logger/logger_service.dart';
import 'package:serial_port_win32/serial_port_win32.dart';

/// 카드 배출기 시리얼 통신 클래스
/// ONEPLUS Card Dispenser RS-232 통신 사양서 기반
class CardDispenserSerial {
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

  CardDispenserSerial({String? portName}) : _portName = portName;

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

  /// 시리얼 포트 연결  ///
  /// [portName] 예: 'COM1', 'COM3' (Windows)
  Future<bool> connect(String portName) async {
    try {
      // 이미 연결되어 있으면 먼저 닫기
      if (_isConnected && _port != null) {
        await disconnect();
      }

      _portName = portName;

      // 시리얼 포트 생성 및 설정
      // Windows API 상수 값 사용:
      // NOPARITY = 0, ONESTOPBIT = 0, CBR_9600 = 9600
      _port = SerialPort(
        portName,
        openNow: false,
        ByteSize: dataBits,
        BaudRate: baudRate, // 9600
        StopBits: 0, // ONESTOPBIT = 0
        Parity: 0, // NOPARITY = 0
      );

      // 포트 열기
      await _port!.open();

      // 연결 확인
      if (_port!.isOpened) {
        _isConnected = true;
        logger.i('Card dispenser connected to $portName');
        return true;
      } else {
        logger.e('Failed to open serial port $portName');
        return false;
      }
    } catch (e) {
      logger.e('Failed to connect to card dispenser', error: e);
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
      }
      _isConnected = false;
      _port = null;
      logger.i('Card dispenser disconnected');
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
    final checksum = _calculateChecksum(cmd, data1, data2);
    return Uint8List.fromList([
      stxByte,
      cmd,
      data1,
      data2,
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
        try {
          _port!.readBytes(1000, timeout: const Duration(milliseconds: 10));
        } catch (e) {
          // 버퍼가 비어있으면 무시
        }

        // 패킷 전송
        final writeSuccess = await _port!.writeBytesFromUint8List(packet, timeout: timeoutMs);
        if (!writeSuccess) {
          throw Exception('Failed to write packet');
        }
        logger.d('Sent packet: ${packet.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ')}');

        // 응답 수신 대기
        final timeout = Duration(milliseconds: timeoutMs);
        Uint8List? response;

        try {
          // 정확히 5바이트 읽기 (타임아웃 적용)
          response = await _port!.readFixedSizeBytes(packetSize).timeout(timeout, onTimeout: () {
            throw TimeoutException('Read timeout after ${timeoutMs}ms');
          });
        } catch (e) {
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

        logger.d('Received packet: ${response.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ')}');

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
  Future<bool> healthCheck() async {
    try {
      // '?' = 0x3F
      final response = await _sendCommand(cmdHealthCheck, 0x49, 0x3F);
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

  /// 초기화 (Reset)
  ///
  /// 명령: "$" + "I" + 0x00 + 0x00
  /// 응답: "$" + "i" + "n" + "s" + "!" (정상) 또는 "$" + "n" + "s" + "!" (불능)
  Future<bool> reset() async {
    try {
      final response = await _sendCommand(cmdReset, 0x00, 0x00);
      if (response != null) {
        // 정상 응답: "i" + "n" + "s" + "!" 또는 "I" + "N" + "S" + "!"
        final isSuccess = (response[1] == 0x69 && response[2] == 0x6E && response[3] == 0x73) ||
            (response[1] == 0x49 && response[2] == 0x4E && response[3] == 0x53);
        return isSuccess;
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
        // 정상 응답: "h" + 0x00 + "a" 또는 "H" + 0x00 + "A"
        final isSuccess = (response[1] == 0x68 && response[3] == 0x61) || (response[1] == 0x48 && response[3] == 0x41);
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
