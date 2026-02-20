import 'package:vending_kiosk/core/common/logger/logger_service.dart';
import 'package:serial_port_win32/serial_port_win32.dart';

/// COM 포트 연결 테스트 유틸리티
/// 관리자 권한 확인 및 포트 접근 가능 여부 테스트
class SerialPortTester {
  /// 사용 가능한 모든 COM 포트 목록 출력
  static List<String> listAvailablePorts() {
    try {
      final ports = SerialPort.getAvailablePorts();
      logger.i('===== 사용 가능한 COM 포트 =====');
      if (ports.isEmpty) {
        logger.w('감지된 COM 포트가 없습니다.');
        logger.w('1. 장치가 연결되어 있는지 확인하세요.');
        logger.w('2. 드라이버가 설치되어 있는지 확인하세요.');
      } else {
        for (final port in ports) {
          logger.i('  - $port');
        }
      }
      return ports;
    } catch (e) {
      logger.e('포트 목록 조회 실패', error: e);
      return [];
    }
  }

  /// 특정 포트 연결 테스트
  static Future<String> testPortConnection(String portName) async {
    logger.i('===== $portName 연결 테스트 시작 =====');

    SerialPort? port;
    try {
      // 포트 생성
      logger.i('1. SerialPort 객체 생성 중...');
      port = SerialPort(
        portName,
        openNow: false,
        BaudRate: 9600,
        ByteSize: 8,
        StopBits: 0,
        Parity: 0,
      );
      logger.i('   ✓ SerialPort 객체 생성 완료');

      // 포트 열기 시도
      logger.i('2. 포트 열기 시도 중...');
      await port.open();

      if (port.isOpened) {
        logger.i('   ✓ 포트 열기 성공!');
        logger.i('   - 포트가 정상적으로 열렸습니다.');
        logger.i('   - 관리자 권한이 있습니다.');

        // 포트 닫기
        port.close();
        logger.i('   ✓ 포트 닫기 완료');

        return '성공: $portName 포트에 정상 접근 가능';
      } else {
        logger.e('   ✗ 포트가 열리지 않았습니다 (isOpened = false)');
        return '실패: 포트가 열리지 않음';
      }
    } catch (e) {
      final errorMsg = e.toString();
      logger.e('   ✗ 포트 열기 실패', error: e);

      // Win32 에러 코드 파싱
      final match = RegExp(r'win32 error code is (\d+)').firstMatch(errorMsg);
      if (match != null) {
        final code = int.parse(match.group(1)!);
        final diagnosis = _diagnoseWin32Error(code);
        logger.e('   Win32 에러 코드: $code');
        logger.e('   진단: $diagnosis');
        return '실패 (Error $code): $diagnosis';
      }

      return '실패: $errorMsg';
    } finally {
      try {
        port?.close();
      } catch (e) {
        // 무시
      }
    }
  }

  /// Win32 에러 코드 진단
  static String _diagnoseWin32Error(int code) {
    switch (code) {
      case 0:
        return '포트가 아직 해제되지 않았습니다. 잠시 후 다시 시도하세요.';
      case 2:
        return 'COM 포트가 존재하지 않습니다. 장치 관리자에서 포트 번호를 확인하세요.';
      case 5:
        return '액세스 거부됨.\n'
            '   해결 방법:\n'
            '   1. 이 프로그램을 관리자 권한으로 실행하세요.\n'
            '   2. 다른 프로그램(Arduino IDE, PuTTY 등)이 이 포트를 사용 중이지 않은지 확인하세요.\n'
            '   3. 장치 관리자에서 해당 포트를 "사용 안 함" 후 다시 "사용"으로 설정해보세요.';
      case 31:
        return '장치가 응답하지 않습니다. USB 케이블을 다시 연결하세요.';
      case 32:
        return '다른 프로세스가 이 포트를 사용 중입니다.\n'
            '   작업 관리자에서 시리얼 관련 프로그램을 종료하거나,\n'
            '   이 앱의 이전 인스턴스를 종료하세요.';
      case 121:
        return '타임아웃. 장치가 연결되어 있지 않거나 응답하지 않습니다.';
      case 1167:
        return '장치가 준비되지 않았습니다. 드라이버를 확인하세요.';
      default:
        return '알 수 없는 에러 (코드: $code)';
    }
  }

  /// 전체 진단 실행
  static Future<void> runFullDiagnostics({String? specificPort}) async {
    logger.i('');
    logger.i('═══════════════════════════════════════');
    logger.i('  카드 배출기 COM 포트 진단 도구');
    logger.i('═══════════════════════════════════════');
    logger.i('');

    // 1. 사용 가능한 포트 목록
    final ports = listAvailablePorts();
    logger.i('');

    // 2. 특정 포트 테스트
    if (specificPort != null) {
      logger.i('');
      final result = await testPortConnection(specificPort);
      logger.i('');
      logger.i('테스트 결과: $result');
    } else if (ports.isNotEmpty) {
      // 모든 포트 테스트
      logger.i('');
      logger.i('===== 모든 포트 연결 테스트 =====');
      for (final port in ports) {
        logger.i('');
        final result = await testPortConnection(port);
        logger.i('$port: $result');
        await Future.delayed(Duration(milliseconds: 500));
      }
    }

    logger.i('');
    logger.i('═══════════════════════════════════════');
  }
}
