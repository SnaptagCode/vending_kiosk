import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:vending_kiosk/core/common/extensions/build_context.dart';
import 'package:vending_kiosk/core/common/extensions/color.dart';
import 'package:vending_kiosk/core/common/logger/logger_service.dart';
import 'package:vending_kiosk/core/data/data.dart';
import 'package:vending_kiosk/core/data/models/request/update_maintenance_request.dart';
import 'package:vending_kiosk/core/services/card_dispenser_service.dart';
import 'package:vending_kiosk/core/ui/theme/kiosk_colors.dart';
import 'package:vending_kiosk/core/ui/widget/dialog_helper.dart';
import 'package:vending_kiosk/locale_keys.dart';
import 'package:vending_kiosk/presentation/home/maintenance_provider.dart';
import 'package:vending_kiosk/presentation/home/payment/payment_failed_type.dart';
import 'package:vending_kiosk/presentation/home/payment_response_state.dart';
import 'package:vending_kiosk/presentation/home/print_quantity_provider.dart';
import 'package:vending_kiosk/presentation/kiosk_shell/kiosk_info_service.dart';
import 'package:vending_kiosk/presentation/print/dispense_progress_provider.dart';
import 'package:vending_kiosk/presentation/routers/router.dart';
import 'package:vending_kiosk/presentation/print/print_process_screen_provider.dart';

class PrintProcessScreen extends ConsumerStatefulWidget {
  const PrintProcessScreen({super.key});

  @override
  ConsumerState<PrintProcessScreen> createState() => _PrintProcessScreenState();
}

class _PrintProcessScreenState extends ConsumerState<PrintProcessScreen> {
  bool _progressCompleted = false;
  bool _printStarted = false;

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _printStarted) return;
      _printStarted = true;
      ref.read(printProcessScreenProviderProvider.notifier).startPrint();
    });
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(printProcessScreenProviderProvider, (previous, next) async {
      if (next.isLoading) return;
      await next.when(
        error: (error, stack) async {
          errorLogging(error.toString(), stack);

          final printJobId = ref.read(printJobIdProvider);
          if (printJobId != null) {
            ref.read(printJobIdProvider.notifier).state = null;
            return;
          }

          if (error is InsufficientCardStockException) {
            final result = await DialogHelper.showInsufficientCardStockDialog(context);
            if (result) {
              await _resetAndGoHome(context);
            }
            return;
          }

          ref.read(maintenanceErrorProvider.notifier).state = true;
          await DialogHelper.showContactManagerDialog(context);
          return await _resetAndGoHome(context);
        },
        loading: () => null,
        data: (_) async {
          _progressCompleted = true;

          final printJobId = ref.read(printJobIdProvider);
          if (printJobId != null) {
            await ref.read(kioskRepositoryProvider).succeedVendingPrintJob(printJobId);
          }

          ref.read(paymentResponseStateProvider.notifier).reset();

          final isReprint = ref.read(reprintIdsProvider.notifier).state != null;
          ref.read(reprintIdsProvider.notifier).state = null;

          final current = ref.read(dispenseProgressNotifierProvider).current;
          if (current == 0) {
            await ref.read(kioskRepositoryProvider).updateMaintenance(
                  ref.read(kioskInfoServiceProvider)!.kioskMachineId,
                  UpdateMaintenanceRequest(isUnderMaintenance: true),
                );
          }

          await DialogHelper.showPrintCompleteDialog(
            context,
            onButtonPressed: () {
              ref.read(printQuantityNotifierProvider.notifier).reset();
              if (printJobId != null) {
                ref.read(printJobIdProvider.notifier).state = null;
                HomeRouteData().go(context);
              } else if (isReprint) {
                PaymentHistoryRouteData().go(context);
              } else {
                HomeRouteData().go(context);
              }
            },
          );
        },
      );
    });

    final kioskInfo = ref.read(kioskInfoServiceProvider);
    final buttonColor =
        kioskInfo?.mainButtonColor != null ? kioskInfo!.mainButtonColor.toColor() : const Color(0xFF4CAF50);
    final buttonTextColor = kioskInfo?.buttonTextColor != null ? kioskInfo!.buttonTextColor.toColor() : Colors.white;

    return DefaultTextStyle(
      style: TextStyle(
        fontFamily: context.locale.languageCode == 'ja' ? 'MPLUSRounded' : 'Cafe24Ssurround2',
      ),
      child: Center(
        child: Column(
          children: [
            SizedBox(height: 60.h),
            Text.rich(
              textAlign: TextAlign.center,
              TextSpan(
                children: [
                  TextSpan(
                    text: '${LocaleKeys.sub03_txt_01.tr()}\n',
                    style: context.typography.vendingTitle1B.copyWith(color: buttonColor),
                  ),
                  TextSpan(
                    text: LocaleKeys.please_wait.tr(),
                    style: context.typography.vendingTitle1B.copyWith(color: buttonTextColor),
                  ),
                ],
              ),
            ),
            SizedBox(height: 24.h),
            Text(
              LocaleKeys.sub03_txt_03.tr(),
              textAlign: TextAlign.center,
              style: context.typography.vendingBody3B.copyWith(color: buttonTextColor),
            ),
            SizedBox(height: 44.h),
            Image.asset(
              'assets/adImages/printing_img.png',
              width: 740.w,
              height: 410.h,
              fit: BoxFit.fill,
            ),
            SizedBox(height: 21.h),
            _PrintProgressBar(),
            SizedBox(height: 16.h),
            _PrintCountText(progressCompleted: _progressCompleted),
            SizedBox(height: 40.h),
          ],
        ),
      ),
    );
  }

  /// 에러 발생 후 공통 처리: 수량 초기화 → 정비 상태 설정(재출력 아닐 때) → 화면 이동
  Future<void> _resetAndGoHome(BuildContext context) async {
    ref.read(paymentResponseStateProvider.notifier).reset();
    ref.read(printQuantityNotifierProvider.notifier).reset();

    final printJobId = ref.read(printJobIdProvider);
    ref.read(printJobIdProvider.notifier).state = null;

    final isReprint = ref.read(reprintIdsProvider.notifier).state != null;
    ref.read(reprintIdsProvider.notifier).state = null;

    if (printJobId != null) {
      HomeRouteData().go(context);
      return;
    }

    if (!isReprint) {
      await ref.read(kioskRepositoryProvider).updateMaintenance(
            ref.read(kioskInfoServiceProvider)!.kioskMachineId,
            UpdateMaintenanceRequest(isUnderMaintenance: true),
          );
    }
    if (isReprint) {
      PaymentHistoryRouteData().go(context);
    } else {
      HomeRouteData().go(context);
    }
  }

  void errorLogging(String error, StackTrace stack) {
    logger.e('Print process error', error: error, stackTrace: stack);
    final machineId = ref.read(kioskInfoServiceProvider)?.kioskMachineId ?? 0;
    SlackLogService().sendErrorLogToSlack('*[MachineId : $machineId]*, Print process error\nError: $error');
  }
}

class _PrintProgressBar extends ConsumerWidget {
  const _PrintProgressBar();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final kioskColors = context.theme.extension<KioskColors>()!;
    final quantity = ref.watch(printQuantityNotifierProvider);
    final progressValue = quantity.total > 0 ? quantity.current / quantity.total : 0.0;

    return SizedBox(
      width: 480.w,
      height: 29.h,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20.r),
          color: kioskColors.progressBarBgColor,
        ),
        child: Padding(
          padding: EdgeInsets.all(3.5.r),
          child: Stack(
            children: [
              FractionallySizedBox(
                widthFactor: progressValue,
                heightFactor: 1,
                alignment: Alignment.centerLeft,
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(17.r),
                    gradient: LinearGradient(
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                      colors: [
                        kioskColors.progressBarStartColor,
                        kioskColors.progressBarEndColor,
                      ],
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: kioskColors.progressBarStartColor.withValues(alpha: 0.8),
                        blurRadius: 8,
                        spreadRadius: 0,
                        offset: Offset.zero,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 출력 개수를 텍스트로 표시 (예: 2 / 5)
class _PrintCountText extends ConsumerWidget {
  const _PrintCountText({required this.progressCompleted});

  final bool progressCompleted;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final quantity = ref.watch(printQuantityNotifierProvider);
    final current = quantity.current;
    final total = quantity.total;

    final displayCurrent = total == 0 ? 0 : (progressCompleted ? total : current);

    final kioskColors = context.kioskColors;
    final textShadow = [
      Shadow(
        color: Colors.black.withValues(alpha: 0.2),
        offset: const Offset(0, 6),
        blurRadius: 4,
      ),
    ];

    final baseStyle = context.typography.vendingBody2B
        .copyWith(fontSize: 36.sp, letterSpacing: 1.8, height: 1.35, color: Colors.white, shadows: textShadow);

    return RichText(
      textAlign: TextAlign.center,
      text: TextSpan(
        children: [
          WidgetSpan(
            alignment: PlaceholderAlignment.baseline,
            baseline: TextBaseline.alphabetic,
            child: ShaderMask(
              shaderCallback: (bounds) => LinearGradient(
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
                colors: [
                  kioskColors.progressBarStartColor,
                  kioskColors.progressBarEndColor,
                ],
              ).createShader(
                Rect.fromLTWH(0, 0, bounds.width, bounds.height),
              ),
              child: Text('$displayCurrent', style: baseStyle),
            ),
          ),
          TextSpan(text: ' / ', style: baseStyle),
          TextSpan(text: '$total', style: baseStyle),
        ],
      ),
    );
  }
}
