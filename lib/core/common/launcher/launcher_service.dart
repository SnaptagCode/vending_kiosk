import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:vending_kiosk/core/common/logger/logger_service.dart';

/// dart:io exit()의 대안. Windows에서 Win32 TerminateProcess를 FFI로 직접 호출.
///
/// dart:io exit()은 내부에서 _EventHandler._shutdown()을 먼저 실행하여
/// InternetConnectionChecker · Dio 소켓 정리 도중 수 초간 블로킹되고
/// Flutter Windows 창이 "응답없음" 상태로 굳어버리는 문제가 있음.
/// TerminateProcess는 해당 정리 단계를 건너뛰고 OS가 즉시 프로세스를 종료함.
void terminateProcess([int exitCode = 0]) {
  if (Platform.isWindows) {
    logger.d('terminateProcess');
    try {
      final kernel32 = DynamicLibrary.open('kernel32.dll');
      final terminateFn =
          kernel32.lookupFunction<Int32 Function(IntPtr, Uint32), int Function(int, int)>('TerminateProcess');
      logger.d('terminateFn: $terminateFn');
      final getHandleFn = kernel32.lookupFunction<IntPtr Function(), int Function()>('GetCurrentProcess');
      logger.d('getHandleFn: $getHandleFn');
      terminateFn(getHandleFn(), exitCode);
      return;
    } catch (_) {}
  }
  exit(exitCode);
}

class ForceUpdateWriter {
  static Future<void> writeForceUpdateTrue() async {
    final home = Platform.environment['USERPROFILE']; // Windows 전용
    if (home == null) throw Exception("홈 디렉토리를 가져올 수 없습니다.");

    final snaptagDir = Directory(p.join(home, 'Snaptag'));
    if (!snaptagDir.existsSync()) {
      snaptagDir.createSync(recursive: true);
    }

    final forceUpdatePath = p.join(snaptagDir.path, "forceUpdate.json");
    final forceUpdateFile = File(forceUpdatePath);

    final content = json.encode({"force_update": true});
    await forceUpdateFile.writeAsString(content);

    print("forceUpdate.json에 force_update: true 기록 완료");
  }
}

class LauncherPathUtil {
  static Future<String> getLauncherPath() async {
    final home = Platform.environment['USERPROFILE'];
    if (home == null) throw Exception("홈 디렉토리를 가져올 수 없습니다.");

    final launcherDir = Directory(p.join(home, 'photoCode_launcher'));

    if (!launcherDir.existsSync()) {
      launcherDir.createSync(recursive: true);
    }

    final launcherPath = p.join(launcherDir.path, 'kiosk_app_launcher.exe');
    return launcherPath;
  }
}
