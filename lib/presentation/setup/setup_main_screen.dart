import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:vending_kiosk/core/common/constants/alert_key.dart';
import 'package:vending_kiosk/core/common/constants/image_paths.dart';
import 'package:vending_kiosk/core/common/extensions/build_context.dart';
import 'package:vending_kiosk/core/common/logger/logger_service.dart';
import 'package:vending_kiosk/core/common/logger/slack_log_service.dart';
import 'package:vending_kiosk/core/common/sound/sound_manager.dart';
import 'package:vending_kiosk/core/data/repositories/kiosk_repository.dart';
import 'package:vending_kiosk/core/data/repositories/payment_repository.dart';
import 'package:vending_kiosk/core/data/models/enums/keypad_mode.dart';
import 'package:vending_kiosk/presentation/kiosk_shell/kiosk_info_service.dart';
import 'package:vending_kiosk/presentation/core/card_count_provider.dart';
import 'package:vending_kiosk/presentation/routers/router.dart';
import 'package:vending_kiosk/presentation/setup/card_dispenser_connect_state.dart';
import 'package:vending_kiosk/presentation/setup/setup_main_screen_provider.dart';
import 'package:vending_kiosk/presentation/setup/alert_definition_provider.dart';
import 'package:vending_kiosk/core/ui/widget/dialog_helper.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:vending_kiosk/core/providers/version_notifier.dart';
import 'package:vending_kiosk/core/common/launcher/launcher_service.dart';

class SetupMainScreen extends ConsumerStatefulWidget {
  const SetupMainScreen({super.key});

  @override
  ConsumerState<SetupMainScreen> createState() => _SetupMainScreenState();
}

class _SetupMainScreenState extends ConsumerState<SetupMainScreen> {
  Timer? _timer;

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _onRunEventTap(BuildContext context) async {
    await SoundManager().playSound();

    final kioskInfo = ref.read(kioskInfoServiceProvider);

    final isPaymentDeviceReady = await _checkPaymentDevice();
    if (!isPaymentDeviceReady) return;

    logger.d(
        'kioskInfo: $kioskInfo kioskEventId: ${kioskInfo?.kioskEventId} kioskMachineId: ${kioskInfo?.kioskMachineId}');
    if (kioskInfo == null) {
      if (kioskInfo?.kioskEventId == 0 ||
          kioskInfo?.kioskEventId == null ||
          kioskInfo?.kioskMachineId == 0 ||
          kioskInfo?.kioskMachineId == null) {
        await DialogHelper.showSetupDialog(
          context,
          title: '이벤트를 실행하려면\n키오스크 기기번호를 입력해 주세요.',
        );
        return;
      }
    }

    ref.read(setupMainScreenNotifierProvider.notifier).writePhotocodeMeta();

    final confirmed = await DialogHelper.showSetupDialog(
      context,
      title: '이벤트를 실행합니다.',
      showCancelButton: true,
    );
    if (!confirmed) return;

    await _startEventFlow(context);
  }

  Future<bool> _checkPaymentDevice() async {
    try {
      final response = await ref.read(paymentRepositoryProvider).check();
      SlackLogService().sendLogToSlack("Payment Device check: $response");

      return true;
    } catch (e) {
      SlackLogService().sendErrorLogToSlack("Payment Device check: $e");

      DialogHelper.showSetupDialog(
        context,
        title: '리더기 점검',
        content: '리더기 응답이 없습니다.\n연결 상태를 확인한 뒤 다시 시도해 주세요.',
      );
      return false;
    }
  }

  Future<void> _startEventFlow(BuildContext context) async {
    final versionState = ref.read(versionStateProvider);
    final currentVersion = versionState.currentVersion;
    final latestVersion = versionState.latestVersion;
    final machineId = ref.read(kioskInfoServiceProvider)?.kioskMachineId ?? 0;
    final kioskEventId = ref.read(kioskInfoServiceProvider)?.kioskEventId ?? 0;
    final cardCountState = ref.read(cardCountProvider);

    await ref.read(kioskRepositoryProvider).deleteEndMark(
          kioskEventId: kioskEventId,
          machineId: machineId,
          remainingSingleSidedCount: cardCountState.remainingSingleSidedCount,
        );

    SlackLogService()
        .sendLogToSlack('machineId:$machineId, currentVersion:$currentVersion, latestVersion:$latestVersion');

    HomeRouteData().go(context);

    SlackLogService().sendInspectionEndBroadcastLogToSlack(InfoKey.inspectionEnd.key);
  }

  @override
  Widget build(BuildContext context) {
    ref.read(alertDefinitionProvider);
    final setupMainViewModel = ref.watch(setupMainScreenNotifierProvider);
    final currentVersion = setupMainViewModel.currentVersion;
    final isUpdateAvailable = setupMainViewModel.isUpdateAvailable;
    final isConnectedCardDispenser = setupMainViewModel.cardDispenserState == CardDispenserConnectState.connected;
    final isCheckingDispenser = setupMainViewModel.isCheckingDispenser;
    final getInfoByKey = setupMainViewModel.getInfoByKey;

    return Theme(
      data: Theme.of(context).copyWith(
        textTheme: Theme.of(context).textTheme.apply(
              fontFamily: 'Pretendard',
            ),
      ),
      child: Scaffold(
        backgroundColor: Color(0xFFF2F2F2),
        appBar: AppBar(
          centerTitle: false,
          title: SvgPicture.asset(
            SnaptagSvg.snaptagLogo,
            width: 160.w,
          ),
          actions: [
            InkWell(
              onTap: () async {
                final result = await DialogHelper.showSetupDialog(
                  context,
                  title: '프로그램을 종료합니다.',
                  showCancelButton: true,
                );
                if (!result) return;
                try {
                  await ref
                      .read(setupMainScreenNotifierProvider.notifier)
                      .exitKioskApp()
                      .timeout(const Duration(seconds: 5));
                } catch (_) {}

                logger.d('exit(0)');
                terminateProcess();
              },
              child: SvgPicture.asset(
                SnaptagSvg.off,
                width: 44.w,
              ),
            ),
            SizedBox(width: 30.w),
          ],
        ),
        body: Container(
          decoration: BoxDecoration(
            image: DecorationImage(
              image: AssetImage(SnaptagImages.setupBackground),
              fit: BoxFit.fill,
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Center(
                child: Text(
                  '관리자 모드',
                  style: context.typography.kioksNum1SB,
                ),
              ),
              SizedBox(height: 50.h),
              Center(
                child: Text(
                  '*카드 수량 입력 후 이벤트를 실행 해주세요. (최대 ${setupMainViewModel.cardCapacity}장)',
                  style: context.typography.kioskBody1B.copyWith(color: Colors.red),
                ),
              ),
              SizedBox(
                height: 10,
              ),
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SizedBox(
                    width: 240.w,
                    height: 80.h,
                    child: Align(
                      alignment: Alignment.center,
                      child: Text(
                        '카드 수량',
                        textAlign: TextAlign.center,
                        style: context.typography.kioskBody1B.copyWith(color: Colors.black),
                      ),
                    ),
                  ),
                  //SizedBox(width: 40.w),
                  Container(
                    width: 520.w,
                    height: 80.h,
                    //padding: EdgeInsets.only(top: 50.w),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      border: Border.all(color: Colors.black),
                      borderRadius: const BorderRadius.all(Radius.circular(12)),
                    ),
                    child: InkWell(
                      borderRadius: const BorderRadius.all(Radius.circular(12)),
                      onTap: () async {
                        String? value = await DialogHelper.showKeypadDialog(context, mode: ModeType.card);

                        if (value == null || value.isEmpty) return; // 값이 없으면 종료

                        int cardNumber = int.parse(value);

                        if (cardNumber > setupMainViewModel.cardCapacity) {
                          await DialogHelper.showSetupDialog(context,
                              title: '입력 수량 초과', content: '최대 ${setupMainViewModel.cardCapacity}장까지 입력 가능합니다.');
                          return;
                        }

                        await ref
                            .read(setupMainScreenNotifierProvider.notifier)
                            .rechargeCardStock(cardNumber: cardNumber);
                      },
                      child: Align(
                        alignment: Alignment.center,
                        child: Text((setupMainViewModel.cardCurrentCount).toString(),
                            textAlign: TextAlign.center,
                            style: context.typography.kioskBody2B.copyWith(color: Colors.black)),
                      ),
                    ),
                  ),
                ],
              ),
              SizedBox(
                height: 80.h,
                width: 760.w, //780
                child: Divider(
                  thickness: 1.h,
                  height: 0,
                ),
              ),
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // getInfoByKey가 true면: 이벤트 미리보기 숨김, 이벤트 실행 -> 출력 내역
                  // getInfoByKey가 false면: 이벤트 미리보기 -> 출력 내역 -> 이벤트 실행
                  if (!getInfoByKey) ...[
                    Padding(
                      padding: EdgeInsets.all(10.w),
                      child: SizedBox(
                        width: 260.w,
                        height: 314.h,
                        child: SetupMainCard(
                          label: '이벤트\n미리보기',
                          assetName: SnaptagSvg.eventPreview,
                          onTap: () async {
                            await SoundManager().playSound();

                            KioskInfoRouteData().go(context);
                          },
                        ),
                      ),
                    ),
                  ],
                  if (getInfoByKey) ...[
                    Padding(
                      padding: EdgeInsets.all(10.w),
                      child: SizedBox(
                        width: 260.w,
                        height: 314.h,
                        child: SetupMainCard(
                          label: '이벤트\n실행',
                          assetName: SnaptagSvg.eventRun,
                          onTap: () async {
                            await _onRunEventTap(context);
                          },
                        ),
                      ),
                    ),
                    Padding(
                      padding: EdgeInsets.all(10.w),
                      child: SizedBox(
                        width: 260.w,
                        height: 314.h,
                        child: SetupMainCard(
                          label: '출력 내역',
                          assetName: SnaptagSvg.payment,
                          onTap: () async {
                            await SoundManager().playSound();
                            PaymentHistoryRouteData().go(context);
                          },
                        ),
                      ),
                    ),
                  ] else ...[
                    Padding(
                      padding: EdgeInsets.all(10.w),
                      child: SizedBox(
                        width: 260.w,
                        height: 314.h,
                        child: SetupMainCard(
                          label: '출력 내역',
                          assetName: SnaptagSvg.payment,
                          onTap: () async {
                            await SoundManager().playSound();
                            PaymentHistoryRouteData().go(context);
                          },
                        ),
                      ),
                    ),
                    Padding(
                      padding: EdgeInsets.all(10.w),
                      child: SizedBox(
                        width: 260.w,
                        height: 314.h,
                        child: SetupMainCard(
                          label: '이벤트\n실행',
                          assetName: SnaptagSvg.eventRun,
                          onTap: () async {
                            await _onRunEventTap(context);
                          },
                        ),
                      ),
                    ),
                  ],
                ],
              ),
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Padding(
                    padding: EdgeInsets.all(10.w),
                    child: SizedBox(
                      width: 260.w,
                      height: 314.h,
                      child: SetupMainCard(
                        label: isConnectedCardDispenser
                            ? '카드 배출기\n사용가능'
                            : isCheckingDispenser
                                ? '카드 배출기\n연결 중...'
                                : '카드 배출기\n준비중',
                        textColor: isConnectedCardDispenser ? Color(0xFF1C1C1C) : Color(0xFFD5D5D5),
                        assetName: isConnectedCardDispenser
                            ? SnaptagSvg.printConnect
                            : isCheckingDispenser
                                ? SnaptagSvg.printError
                                : SnaptagSvg.refresh,
                        isLoading: isCheckingDispenser,
                        onTap: isConnectedCardDispenser || isCheckingDispenser
                            ? null
                            : () => ref.read(setupMainScreenNotifierProvider.notifier).retryCardDispenserConnection(),
                      ),
                    ),
                  ),
                  Padding(
                    padding: EdgeInsets.all(10.w),
                    child: SizedBox(
                      width: 260.w,
                      height: 314.h,
                      child: SetupUpdateCard(
                        title: '현재 버전',
                        version: currentVersion,
                        buttonName: '업데이트',
                        isActive: isUpdateAvailable,
                        onUpdatePressed: () async {
                          final result = await DialogHelper.showKioskDialog(context,
                              title: '업데이트 하시겠습니까?',
                              contentText: '업데이트 시 앱이 재시작 됩니다.',
                              cancelButtonText: '취소',
                              confirmButtonText: '완료');
                          if (result) {
                            try {
                              final launcherPath = await LauncherPathUtil.getLauncherPath();
                              await ForceUpdateWriter.writeForceUpdateTrue();
                              print("Process.start");
                              await Process.start(
                                launcherPath,
                                ['f'],
                                runInShell: true,
                                mode: ProcessStartMode.detached,
                              );
                              print("Process.start(launcherPath, ['f'])");
                              terminateProcess();
                            } catch (e) {
                              print("런처 실행 실패: $e");
                            }
                          } else {}
                        },
                      ),
                    ),
                  ),
                  Padding(
                    padding: EdgeInsets.all(10.w),
                    child: SizedBox(
                      width: 260.w,
                      height: 314.h,
                      child: SetupMainCard(
                        label: '서비스 점검',
                        assetName: SnaptagSvg.maintenance,
                        onTap: () async {
                          SlackLogService().sendBroadcastLogToSlack(InfoKey.serviceMaintenanceEnter.key);
                          await SoundManager().playSound();
                          MaintenanceRouteData().go(context);
                        },
                      ),
                    ),
                  ),
                ],
              ),
              SizedBox(
                height: 40.h,
              ),
              SizedBox(
                  width: 820.w, //780
                  height: 88.h,
                  child: isUpdateAvailable
                      ? UpdateNoticeBanner(latestVersion: setupMainViewModel.latestVersion)
                      : SizedBox()),
            ],
          ),
        ),
      ),
    );
  }
}

class SetupMainCard extends StatelessWidget {
  final String label;
  final String? assetName;
  final void Function()? onTap;
  final Color? textColor;
  final bool isLoading;

  const SetupMainCard({
    super.key,
    required this.label,
    this.assetName,
    this.onTap,
    this.textColor,
    this.isLoading = false,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: Color(0xFFE6E8EB),
          width: 2,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      color: Colors.white,
      child: GestureDetector(
        onTap: onTap,
        child: SizedBox(
          width: double.infinity,
          height: double.infinity,
          child: assetName != null
              ? Column(
                  mainAxisAlignment: MainAxisAlignment.start,
                  children: [
                    SizedBox(height: 10.h),
                    isLoading
                        ? SizedBox(
                            width: 260.w,
                            height: 200.w,
                            child: Center(
                              child: SizedBox(
                                width: 80.w,
                                height: 80.w,
                                child: CircularProgressIndicator(
                                  strokeWidth: 6,
                                  color: Color(0xFF316FFF),
                                ),
                              ),
                            ),
                          )
                        : SvgPicture.asset(
                            assetName ?? '',
                            width: 260.w,
                            height: 200.w,
                            fit: BoxFit.cover,
                          ),
                    Spacer(),
                    Padding(
                      padding: EdgeInsets.only(bottom: 22.h),
                      child: SizedBox(
                        width: 260.w,
                        child: Text(
                          label,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 34.sp,
                            fontWeight: FontWeight.w700,
                            color: textColor ?? Color(0xFF1C1C1C),
                            letterSpacing: -0.1,
                            height: 1.2,
                          ),
                        ),
                      ),
                    ),
                    Spacer(),
                  ],
                )
              : Center(
                  child: SizedBox(
                    width: 260.w,
                    child: Text(
                      label,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 34.sp,
                        fontWeight: FontWeight.w700,
                        color: textColor ?? Color(0xFF1C1C1C),
                        letterSpacing: -0.1,
                        height: 1.2,
                      ),
                    ),
                  ),
                ),
        ),
      ),
    );
  }
}

class SetupSubCard<T> extends ConsumerWidget {
  final String label;
  final T mode;
  final T Function(WidgetRef ref) currentModeSelector;
  final String activeAssetName;
  final String inactiveAssetName;
  final void Function()? onTap;
  const SetupSubCard({
    super.key,
    required this.label,
    required this.mode,
    required this.currentModeSelector,
    required this.activeAssetName,
    required this.inactiveAssetName,
    this.onTap,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final T current = currentModeSelector(ref);
    final bool isActive = current == mode;
    print("current Type: $current");
    print("isActive : $isActive");
    return Padding(
      padding: EdgeInsets.all(8.w),
      child: Container(
        width: 400.w,
        height: 120.h,
        //padding: EdgeInsets.only(top: 50.w),
        decoration: BoxDecoration(
          color: isActive ? Colors.black : Colors.white,
          border: Border.all(
            color: Color(0xFFE6E8EB),
          ),
          borderRadius: const BorderRadius.all(Radius.circular(12)),
        ),
        child: InkWell(
          borderRadius: const BorderRadius.all(Radius.circular(12)),
          onTap: onTap,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.start,
            children: [
              SizedBox(width: 72.5.w), //60
              SvgPicture.asset(
                isActive ? activeAssetName : inactiveAssetName,
                width: 80.w,
                height: 80.w,
              ),
              SizedBox(width: 23.w),
              Align(
                alignment: Alignment.centerRight,
                child: Text(
                  label,
                  textAlign: TextAlign.center,
                  style: isActive
                      ? context.typography.kioskInput2B.copyWith(color: Colors.white)
                      : context.typography.kioskInput2B.copyWith(color: Colors.black),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class SetupUpdateCard extends StatelessWidget {
  final String title;
  final String version;
  final String buttonName;
  final bool isActive;
  final VoidCallback? onUpdatePressed;

  const SetupUpdateCard({
    super.key,
    required this.title,
    required this.version,
    required this.buttonName,
    required this.isActive,
    this.onUpdatePressed,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: Color(0xFFE6E8EB),
          width: 2,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      color: Colors.white,
      child: Container(
        width: 260.w,
        height: 342.h,
        padding: EdgeInsets.only(top: 63.h),
        child: Column(
          children: [
            SizedBox(height: 40.w),
            Text(
              title,
              style: context.typography.kioskBody2B.copyWith(
                color: Color(0xFF999999),
              ),
            ),
            SizedBox(height: 12.w),
            Text(version, style: context.typography.kioskNum2B),
            const Spacer(),
            SizedBox(
              width: 216.w,
              height: 46.h,
              child: ElevatedButton(
                onPressed: isActive ? onUpdatePressed : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: isActive ? Color(0xFF316FFF) : Color(0xFFD5D5D5),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                child: Text(
                  buttonName,
                  style: TextStyle(
                    fontSize: 26.sp,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                    letterSpacing: -0.2,
                    height: 1.0,
                  ),
                ),
              ),
            ),
            SizedBox(height: 24.w),
          ],
        ),
      ),
    );
  }
}

class UpdateNoticeBanner extends StatelessWidget {
  final String latestVersion;

  const UpdateNoticeBanner({
    super.key,
    required this.latestVersion,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 25.w),
      child: Container(
        width: double.infinity,
        padding: EdgeInsets.symmetric(vertical: 16.h, horizontal: 24.w),
        decoration: BoxDecoration(
          color: const Color(0xFF444444),
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black26,
              blurRadius: 4,
              offset: Offset(0, 2),
            ),
          ],
        ),
        child: RichText(
          textAlign: TextAlign.center,
          text: TextSpan(
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Colors.white,
                  fontSize: 20.sp,
                ),
            children: [
              const TextSpan(text: '최신 버전 '),
              TextSpan(
                text: latestVersion,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              TextSpan(
                text: '이 출시되었습니다.\n원활한 이용을 위해 업데이트를 진행해주세요',
                style: TextStyle(color: Color.fromARGB(204, 255, 255, 255)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
