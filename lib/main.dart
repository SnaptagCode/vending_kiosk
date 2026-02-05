import 'dart:async';
import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:vending_kiosk/app.dart';
import 'package:vending_kiosk/core/common/logger/slack_log_service.dart';
import 'package:vending_kiosk/flavors.dart';
import 'package:vending_kiosk/lib.dart';
import 'package:window_manager/window_manager.dart';

void main() async {
  // 인증서 유효성 무시
  HttpOverrides.global = MyHttpOverrides();
  if (kDebugMode) {
    F.appFlavor = Flavor.dev;
  } else {
    F.appFlavor = Flavor.prod;
  }
  await dotenv.load(fileName: "assets/.env");
  final slackCall = SlackLogService();

  // Preserve default FlutterError behavior so debug console shows root causes.
  final FlutterExceptionHandler? originalOnError = FlutterError.onError;
  // Zone으로 감싸서 모든 비동기 에러도 캐치
  runZonedGuarded(
    () async {
      WidgetsFlutterBinding.ensureInitialized();

      // WindowManager 초기화만 수행 (설정은 App에서)
      if (Platform.isWindows) {
        await windowManager.ensureInitialized();
      }

      // ✅ FlutterError 로그 자동 감지
      FlutterError.onError = (FlutterErrorDetails details) {
        // Keep default error presentation in debug (so you can see *why* debugger paused).
        if (kDebugMode) {
          if (originalOnError != null) {
            originalOnError(details);
          } else {
            FlutterError.presentError(details);
          }
        }
        slackCall.sendLogToSlack("[FLUTTER ERROR] ${details.exceptionAsString()}");
      };

      // Catches errors not routed through FlutterError (e.g. platform dispatcher).
      PlatformDispatcher.instance.onError = (error, stack) {
        if (kDebugMode) {
          FlutterError.dumpErrorToConsole(
            FlutterErrorDetails(exception: error, stack: stack),
          );
        }
        slackCall.sendLogToSlack("[DISPATCHER ERROR] $error\nStackTrace: $stack");
        return true;
      };

      await EasyLocalization.ensureInitialized();

      runApp(
        EasyLocalization(
          supportedLocales: const [
            Locale('ko', 'KR'),
            Locale('en', 'US'),
            Locale('ja', 'JP'),
            Locale('zh', 'CN'),
          ],
          path: 'assets/lang',
          fallbackLocale: const Locale('ko', 'KR'),
          child: ProviderScope(
            child: Builder(
              builder: (context) {
                final container = ProviderScope.containerOf(context);
                SlackLogService().init(container);
                return ScreenUtilInit(
                  designSize: const Size(1080, 1920),
                  minTextAdapt: true,
                  splitScreenMode: true,
                  child: App(),
                );
              },
            ),
          ),
        ),
      );
    },
    (error, stackTrace) {
      slackCall.sendLogToSlack("[ZONE ERROR] $error\nStackTrace: $stackTrace");
    },
  );
}

// 🚨 SSL 인증서 오류(HandshakeException) 해결을 위한 설정
// ➤ 신뢰할 수 없는 인증서로 인해 발생하는 HandshakeException을 방지하기 위해 인증서 검증을 무시하는 작업
// ➤ Windows IOT 버전에서 발생한 오류
class MyHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    // '?'를 추가해서 null safety 확보
    return super.createHttpClient(context)
      ..badCertificateCallback = (X509Certificate cert, String host, int port) => true;
  }
}
