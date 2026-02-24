import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:vending_kiosk/core/common/constants/alert_key.dart';
import 'package:vending_kiosk/core/common/constants/image_paths.dart';
import 'package:vending_kiosk/core/common/extensions/build_context.dart';
import 'package:vending_kiosk/core/common/logger/logger_service.dart';
import 'package:vending_kiosk/core/common/logger/slack_log_service.dart';
import 'package:vending_kiosk/core/providers/network_status_provider.dart';
import 'package:vending_kiosk/core/providers/version_notifier.dart';
import 'package:vending_kiosk/core/ui/widget/dialog_helper.dart';
import 'package:vending_kiosk/locale_keys.dart';
import 'package:vending_kiosk/presentation/core/card_count_provider.dart';
import 'package:vending_kiosk/presentation/home/payment_response_state.dart';
import 'package:vending_kiosk/presentation/home/print_quantity_provider.dart';
import 'package:vending_kiosk/presentation/kiosk_shell/kiosk_info_service.dart';
import 'package:vending_kiosk/presentation/routers/router.dart';
import 'package:vending_kiosk/presentation/setup/page_print_provider.dart';
import 'package:vending_kiosk/presentation/print/print_process_screen_provider.dart';

import 'dart:io';
import 'dart:math';

class PrintProcessScreen extends ConsumerStatefulWidget {
  const PrintProcessScreen({super.key});

  @override
  ConsumerState<PrintProcessScreen> createState() => _PrintProcessScreenState();
}

class _PrintProcessScreenState extends ConsumerState<PrintProcessScreen> {
  bool _progressCompleted = false;
  bool _progressFrozen = false;
  bool _printStarted = false;

  @override
  void initState() {
    super.initState();

    // 프린트/카드배출 작업을 "listen 방식"으로 처리: 화면이 그려진 직후 한 번만 시작
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _printStarted) return;
      _printStarted = true;
      ref.read(printProcessScreenProviderProvider.notifier).startPrint();
    });
  }

  @override
  Widget build(BuildContext context) {
    final randomAdImage = getRandomAdImageFilePath(ref);

    // listen 부분에서는 로딩 오버레이 처리를 제거
    ref.listen(printProcessScreenProviderProvider, (previous, next) async {
      if (!next.isLoading) {
        // 로딩이 아닐 때만 처리
        await next.when(
          error: (error, stack) async {
            if (!_progressCompleted && !_progressFrozen) {
              _progressFrozen = true;
            }

            // 슬랙에 에러 로그 전송
            errorLogging(error.toString(), stack);

            // 네트워크 오류인지 체크
            final isNetworkError = ref.read(networkStatusNotifierProvider.notifier).isNetworkError(error);

            // 네트워크 오류라면 카드 단일 카드 수량 확인 후 완료 알럿 표시
            if (isNetworkError) {
              await DialogHelper.showPrintCompleteDialog(
                context,
                onButtonPressed: () {
                  HomeRouteData().go(context);
                },
              );
              return;
            }

            final result = await DialogHelper.showKioskDialog(
              context,
              title: LocaleKeys.alert_title_print_failure.tr(),
              contentText: LocaleKeys.alert_txt_print_failure.tr(),
              confirmButtonText: LocaleKeys.alert_btn_print_failure.tr(),
            );
            if (result) {
              HomeRouteData().go(context);
            }
          },
          loading: () => null,
          data: (_) async {
            if (!_progressCompleted) {
              _progressCompleted = true;
            }

            // Reset payment and quantity state
            ref.read(paymentResponseStateProvider.notifier).reset();

            final isReprint = ref.read(reprintModeProvider);
            if (isReprint) {
              ref.read(reprintModeProvider.notifier).state = false;
            }

            await DialogHelper.showPrintCompleteDialog(
              context,
              onButtonPressed: () {
                if (isReprint) {
                  PaymentHistoryRouteData().go(context);
                } else {
                  HomeRouteData().go(context);
                }
              },
            );
          },
        );
      }
    });
    // NOTE: kioskInfoServiceProvider는 하위 로직/화면에서 사용될 수 있어 watch 유지
    ref.watch(kioskInfoServiceProvider);
    return DefaultTextStyle(
      style: TextStyle(
        fontFamily: context.locale.languageCode == 'ja' ? 'MPLUSRounded' : 'Cafe24Ssurround2',
      ),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.start,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Text(
              LocaleKeys.sub03_txt_01.tr(),
              textAlign: TextAlign.center,
              style: context.typography.kioskBody1B.copyWith(fontSize: 40.sp),
            ),
            SizedBox(height: 23.h),
            Container(
              padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 8.h),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.5), // 원하는 배경색
              ),
              child: Text(
                LocaleKeys.sub03_txt_02.tr(),
                textAlign: TextAlign.center,
                style: context.typography.kioskBody1B.copyWith(fontSize: 30.sp),
              ),
            ),
            SizedBox(height: 30.h),
            randomAdImage == null
                ? Container(
                    width: 1080.w,
                    height: 400.h,
                    decoration: BoxDecoration(border: Border.all(color: Colors.transparent, width: 0.w)),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(10.r),
                      child: SizedBox(
                        child: Image.asset(
                          SnaptagImages.printLoading,
                        ),
                      ),
                    ),
                  )
                : Image.file(
                    File(randomAdImage),
                    fit: BoxFit.fill,
                  ),
            SizedBox(height: 60.h),
            _PrintCountText(progressCompleted: _progressCompleted, progressFrozen: _progressFrozen),
            SizedBox(height: 16.h),
            Text(
              LocaleKeys.sub03_txt_03.tr(),
              textAlign: TextAlign.center,
              style: context.typography.kioskBody2B.copyWith(fontSize: 26.sp),
            ),
          ],
        ),
      ),
    );
  }

  bool checkCardFeederIsEmpty(String errorMessage) {
    return errorMessage.contains('Card feeder is empty');
  }

  void checkCardSingleCardCount() {
    final machineId = ref.read(kioskInfoServiceProvider)?.kioskMachineId ?? 0;

    if (ref.read(cardCountProvider).currentCount < 1) {
      ref.read(pagePrintProvider.notifier).set(PagePrintType.double);
      SlackLogService().sendLogToSlack('*[MachineId : $machineId]*, change pagePrintType double');
    } else {
      ref.read(pagePrintProvider.notifier).set(PagePrintType.single);
      SlackLogService().sendLogToSlack('*[MachineId : $machineId]*, change pagePrintType single');
    }
  }

  void errorLogging(String error, StackTrace stack) {
    logger.e('Print process error', error: error, stackTrace: stack);
    final machineId = ref.read(kioskInfoServiceProvider)?.kioskMachineId ?? 0;
    SlackLogService().sendErrorLogToSlack('*[MachineId : $machineId]*, Print process error\nError: $error');
  }

  /// 사용자 홈 디렉토리를 동기적으로 반환합니다.
  String? getUserDirectorySync() {
    return Platform.environment['USERPROFILE']; // Windows 전용
  }

  /// 최종: 랜덤 이미지 파일 경로 반환
  String? getRandomAdImagePath(WidgetRef ref) {
    final version = ref.read(versionStateProvider).currentVersion;
    final userDir = getUserDirectorySync();

    if (userDir == null) {
      print('❌ 사용자 디렉토리를 불러올 수 없습니다.');
      return null;
    }

    final adImageFolder = Directory(
      '$userDir\\Snaptag\\$version\\assets\\adImages',
    );

    if (!adImageFolder.existsSync()) {
      print('❌ 이미지 폴더가 존재하지 않습니다: ${adImageFolder.path}');
      return null;
    }

    final imageFiles = adImageFolder
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.png') || f.path.endsWith('.jpg') || f.path.endsWith('.jpeg'))
        .toList();

    if (imageFiles.isEmpty) {
      print('❌ 이미지 파일이 없습니다.');
      return null;
    }

    final randomFile = imageFiles[Random().nextInt(imageFiles.length)];
    final fileName = randomFile.uri.pathSegments.last;

    return 'assets/adImages/$fileName';
  }

  String? getRandomAdImageFilePath(WidgetRef ref) {
    final version = ref.read(versionStateProvider).currentVersion;
    final userDir = getUserDirectorySync();
    final machineId = ref.read(kioskInfoServiceProvider)?.kioskMachineId ?? 0;
    if (userDir == null) {
      SlackLogService().sendLogToSlack('machineId: $machineId 배너를 불러오기 위한 사용자 디렉토리를 불러올 수 없습니다.');
      return null;
    }

    final adImageFolder = Directory((machineId == 2 || machineId == 3)
        ? '$userDir\\Snaptag\\$version\\assets\\adImages\\suwon'
        : (machineId == 1 || machineId == 4)
            ? '$userDir\\Snaptag\\$version\\assets\\adImages\\eland'
            : '$userDir\\Snaptag\\$version\\assets\\adImages\\ansan');

    if (!adImageFolder.existsSync()) {
      SlackLogService().sendLogToSlack('machineId: $machineId 배너를 불러오기 위한 이미지 폴더가 존재하지 않습니다.');
      print('❌ 이미지 폴더가 존재하지 않습니다: ${adImageFolder.path}');
      return null;
    }

    final imageFiles = adImageFolder
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.png') || f.path.endsWith('.jpg') || f.path.endsWith('.jpeg'))
        .toList();

    if (imageFiles.isEmpty) {
      SlackLogService().sendLogToSlack('machineId: $machineId 배너를 불러오기 위한 이미지 폴더내부에 이미지가 존재하지 않습니다.');
      return null;
    }

    final randomFile = imageFiles[Random().nextInt(imageFiles.length)];
    return randomFile.path; // ⬅️ 여기서 전체 파일 경로 반환
  }
}

/// 출력 개수를 텍스트로 표시 (예: 2 / 5)
class _PrintCountText extends ConsumerWidget {
  const _PrintCountText({
    required this.progressCompleted,
    required this.progressFrozen,
  });

  final bool progressCompleted;
  final bool progressFrozen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final quantity = ref.watch(printQuantityNotifierProvider);
    final current = quantity.current;
    final total = quantity.total;

    String label;
    if (total == 0) {
      label = '0 / 0';
    } else if (progressCompleted) {
      label = '$total / $total';
    } else if (progressFrozen) {
      label = '$current / $total';
    } else {
      label = '$current / $total';
    }

    return Text(
      label,
      style: context.typography.kioskBody1B.copyWith(
        fontSize: 48.sp,
        color: Colors.white,
      ),
      textAlign: TextAlign.center,
    );
  }
}
