import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:loader_overlay/loader_overlay.dart';
// import 'package:flutter_tts/flutter_tts.dart';
import 'package:vending_kiosk/core/common/extensions/build_context.dart';
import 'package:vending_kiosk/core/common/extensions/color.dart';
import 'package:vending_kiosk/core/common/logger/slack_log_service.dart';
import 'package:vending_kiosk/core/data/models/enums/vending_print_job_type.dart';
import 'package:vending_kiosk/core/data/models/request/update_maintenance_request.dart';
import 'package:vending_kiosk/core/data/models/response/vending_print_polling_response.dart';
import 'package:vending_kiosk/core/data/repositories/kiosk_repository.dart';
import 'package:vending_kiosk/core/ui/widget/dialog_helper.dart';
import 'package:vending_kiosk/locale_keys.dart';
import 'package:vending_kiosk/presentation/home/maintenance_provider.dart';
import 'package:vending_kiosk/presentation/home/payment/payment_failed_type.dart';
import 'package:vending_kiosk/presentation/home/payment/photo_card_preview_screen_provider.dart';
import 'package:vending_kiosk/presentation/home/payment_provider.dart';
import 'package:vending_kiosk/presentation/home/print_quantity_provider.dart';
import 'package:vending_kiosk/presentation/kiosk_shell/home_timeout_provider.dart';
import 'package:vending_kiosk/presentation/kiosk_shell/kiosk_info_service.dart';
import 'package:vending_kiosk/presentation/print/print_process_screen_provider.dart';
import 'package:vending_kiosk/presentation/routers/router.dart';
import 'package:vending_kiosk/presentation/setup/uuid_provider.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  Timer? _maintenanceTimer;
  bool _isCheckingMaintenance = false;
  Timer? _printJobPollingTimer;
  bool _isCheckingPrintJob = false;
  int _printJobFailureCount = 0;
  static const int _maxPrintJobFailures = 3;
  int? _gaveUpPrintJobId;
  int _selectedQuantity = 1;

  @override
  void initState() {
    super.initState();

    _startMaintenancePolling();
    _startPrintJobPolling();
  }

  @override
  void dispose() {
    _maintenanceTimer?.cancel();
    _isCheckingMaintenance = false;
    _printJobPollingTimer?.cancel();
    _isCheckingPrintJob = false;
    super.dispose();
  }

  void _startMaintenancePolling() {
    _maintenanceTimer?.cancel();
    _maintenanceTimer = Timer.periodic(const Duration(seconds: 3), (_) async {
      if (_isCheckingMaintenance) return;
      _isCheckingMaintenance = true;
      try {
        await _checkMaintenance();
      } finally {
        _isCheckingMaintenance = false;
      }
    });
  }

  void _startPrintJobPolling() {
    _printJobPollingTimer?.cancel();
    _printJobPollingTimer = Timer.periodic(const Duration(seconds: 3), (_) async {
      if (_isCheckingPrintJob) return;
      _isCheckingPrintJob = true;
      try {
        await _checkPrintJob();
      } finally {
        _isCheckingPrintJob = false;
      }
    });
  }

  Future<void> _checkPrintJob() async {
    int printJobId = 0;

    // Phase 1: 폴링 API 호출 (실패 시 재시도 카운팅)
    final VendingPrintPollingResponse response;
    try {
      final kioskInfo = ref.read(kioskInfoServiceProvider);
      if (kioskInfo == null) return;

      response = await ref.read(kioskRepositoryProvider).getVendingPrintPolling(kioskInfo.kioskMachineId);
    } catch (e) {
      ref.read(printJobIdProvider.notifier).state = null;
      return;
    }

    if (!response.exists) return;

    // 이미 포기한 job이면 스킵
    if (response.printJobId != null && response.printJobId == _gaveUpPrintJobId) return;

    // 새 job이 오면 실패 카운터 리셋
    if (response.printJobId != _gaveUpPrintJobId) {
      _printJobFailureCount = 0;
    }

    // Phase 2: 작업 처리 (폴링 재시도와 무관)
    try {
      // 선점
      await ref.read(kioskRepositoryProvider).pickVendingPrintJob(response.printJobId!);

      // polling 중단 (이후 print screen으로 이동)
      _printJobPollingTimer?.cancel();

      // 임의출력 처리
      printJobId = response.printJobId!;
      ref.read(printJobIdProvider.notifier).state = printJobId;
      ref.read(printQuantityNotifierProvider.notifier).setQuantity(response.requestCount!);

      // 재출력 처리
      if (response.type == VendingPrintJobType.reprint) {
        ref.read(reprintIdsProvider.notifier).state = response.printedPhotoCardIdList!;
        PrintProcessRouteData().go(context);
        return;
      }

      // 배출 실행
      ref.read(printProcessScreenProviderProvider.notifier).startPrint();

      ref.read(printJobIdProvider.notifier).state = null;
      _printJobFailureCount = 0;
    } catch (e) {
      _printJobFailureCount++;
      if (_printJobFailureCount >= _maxPrintJobFailures) {
        final kioskInfo = ref.read(kioskInfoServiceProvider);
        final name = kioskInfo?.kioskMachineName ?? '';
        final id = kioskInfo?.kioskMachineId ?? '';
        SlackLogService().sendErrorLogToSlack(
          '[$name ($id)] 임의출력/재출력에 상태확인 실패했습니다',
        );
        _gaveUpPrintJobId = response.printJobId;
        _printJobFailureCount = 0;
        // 서버에 job 실패 처리 (pick된 경우에만)
        if (printJobId != 0) {
          try {
            await ref.read(kioskRepositoryProvider).failVendingPrintJob(
                  printJobId: printJobId,
                  failureReason: '키오스크 출력 $_maxPrintJobFailures회 실패',
                );
          } catch (_) {}
        }
      }
      ref.read(printJobIdProvider.notifier).state = null;
    } finally {
      // 임의 출력 처리 후 polling 재개 (3회 실패 시 catch에서 중단됨)
      if (printJobId != 0) {
        _startPrintJobPolling();
      }
    }
  }

  Future<bool> _checkMaintenance() async {
    try {
      final kioskInfo = ref.read(kioskInfoServiceProvider);
      if (kioskInfo == null) return false;

      final uniqueKey = await ref.read(deviceUuidProvider.future);
      final response = await ref.read(kioskRepositoryProvider).getMachineMaintenance(
            machineId: kioskInfo.kioskMachineId,
            uniqueKey: uniqueKey,
          );

      if (mounted) {
        ref.read(maintenanceStateProvider.notifier).state = response.isUnderMaintenance;
      }
      return response.isUnderMaintenance;
    } catch (_) {
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final kiosk = ref.watch(kioskInfoServiceProvider);
    final paymentState = ref.watch(paymentNotifierProvider);

    // 가격 계산
    final unitPrice = kiosk?.photoCardPrice ?? 1000;
    final totalPrice = unitPrice * _selectedQuantity;
    final formattedPrice = NumberFormat.currency(locale: 'ko_KR', symbol: '').format(totalPrice);

    ref.listen<AsyncValue<void>>(
      photoCardPreviewScreenProviderProvider,
      (previous, next) async {
        final timeoutNotifier = ref.read(homeTimeoutNotifierProvider.notifier);

        // 로딩 상태 처리
        if (next.isLoading) {
          if (mounted) {
            context.loaderOverlay.show();
          }
          return;
        }

        // 로딩 오버레이 숨기기
        if (mounted && context.loaderOverlay.visible) {
          context.loaderOverlay.hide();
        }

        // 에러/성공 처리
        await next.when(
          error: (error, stack) async {
            if (mounted) {
              timeoutNotifier.resumeTimer();
            }

            bool handled = false;
            if (error is PaymentFailedException) {
              if (error is InsufficientCardStockException) {
                final result = await DialogHelper.showInsufficientCardStockDialog(context);
                if (result) {
                  await ref.read(kioskRepositoryProvider).updateMaintenance(
                        ref.read(kioskInfoServiceProvider)!.kioskMachineId,
                        UpdateMaintenanceRequest(isUnderMaintenance: true),
                      );
                  _startMaintenancePolling();
                }
                handled = true;
              } else if (error is TimeoutPaymentException) {
                await DialogHelper.showTimeoutPaymentDialog(context);
                handled = true;
              } else if (error.description?.contains('한도') ?? false) {
                await DialogHelper.showCardLimitExceededDialog(context);
                handled = true;
              } else if (error.description?.contains('잔액') ?? false) {
                await DialogHelper.showInsufficientBalanceDialog(context);
                handled = true;
              } else if (error.description?.contains('인증') ?? false) {
                await DialogHelper.showVerificationErrorDialog(context);
                handled = true;
              } else if (error.description?.contains('가맹점') ?? false) {
                await DialogHelper.showMerchantRestrictionDialog(context);
                handled = true;
              }
            }

            if (!handled) {
              await DialogHelper.showPurchaseFailedDialog(context);
            }

            _startPrintJobPolling();
          },
          loading: () => null,
          data: (_) async {
            // 결제 성공 시 출력 화면으로 이동
            PrintProcessRouteData().go(context);
          },
        );
      },
    );

    // mainButtonColor - 버튼/키패드/텍스트 강조
    // buttonTextColor - 버튼 텍스트
    // mainTextColor - 텍스트
    // popupButtonColor - 구분선
    // progressBarBgColor - 진행바/텍스트트 배경

    final buttonColor = kiosk?.mainButtonColor != null ? kiosk!.mainButtonColor.toColor() : const Color(0xFF4CAF50);
    final buttonTextColor = kiosk?.buttonTextColor != null ? kiosk!.buttonTextColor.toColor() : Colors.white;
    final mainTextColor = kiosk?.mainTextColor != null ? kiosk!.mainTextColor.toColor() : Colors.white;
    final popupButtonColor = kiosk?.popupButtonColor != null ? kiosk!.popupButtonColor.toColor() : Colors.white;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Center(
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 80.w),
          child: Column(
            children: [
              // 통합 카드: 수량 선택 + 가격 표시 + 결제 버튼
              Padding(
                padding: EdgeInsetsGeometry.only(top: 62.h),
                child: Container(
                  width: double.infinity,
                  clipBehavior: Clip.antiAlias,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12.r),
                  ),
                  child: Column(
                    children: [
                      // 섹션 1: 타이틀 + 수량 선택 키패드
                      Padding(
                        padding: EdgeInsets.fromLTRB(58.w, 52.h, 58.w, 34.h),
                        child: Column(
                          children: [
                            // 타이틀
                            Text.rich(
                              textAlign: TextAlign.center,
                              TextSpan(
                                children: [
                                  if (LocaleKeys.purchase_title_before.tr().isNotEmpty)
                                    TextSpan(
                                      text: LocaleKeys.purchase_title_before.tr(),
                                      style: context.typography.vendingTitle2B.copyWith(
                                        color: mainTextColor,
                                      ),
                                    ),
                                  TextSpan(
                                    text: LocaleKeys.purchase_title_highlight.tr(),
                                    style: context.typography.vendingTitle2B.copyWith(
                                      color: buttonColor,
                                    ),
                                  ),
                                  if (LocaleKeys.purchase_title_after.tr().isNotEmpty)
                                    TextSpan(
                                      text: LocaleKeys.purchase_title_after.tr(),
                                      style: context.typography.vendingTitle2B.copyWith(
                                        color: mainTextColor,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                            SizedBox(height: 42.h),

                            // 수량 버튼 1~10 (2행)
                            Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    for (int i = 1; i <= 5; i++) ...[
                                      if (i > 1) SizedBox(width: 16.w),
                                      _buildQuantityButton(context, i, buttonColor, mainTextColor),
                                    ],
                                  ],
                                ),
                                SizedBox(height: 16.h),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    for (int i = 6; i <= 10; i++) ...[
                                      if (i > 6) SizedBox(width: 16.w),
                                      _buildQuantityButton(context, i, buttonColor, mainTextColor),
                                    ],
                                  ],
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),

                      // 내부 구분선 (카드 border가 위에 오도록 clipBehavior로 처리)
                      Padding(
                        padding: EdgeInsets.symmetric(horizontal: 1.w),
                        child: Stack(
                          children: [
                            Container(
                              height: 15.h,
                              color: popupButtonColor,
                            ),
                            Container(
                              height: 1,
                              color: const Color(0xFFCACACA),
                            ),
                          ],
                        ),
                      ),

                      // 섹션 2: 가격 표시 + 결제 버튼
                      Padding(
                        padding: EdgeInsets.fromLTRB(58.w, 40.h, 58.w, 34.h),
                        child: Column(
                          children: [
                            // 가격 표시
                            Container(
                              padding: EdgeInsets.only(top: 4.h),
                              width: 789.w,
                              child: Column(
                                children: [
                                  Padding(
                                    padding: EdgeInsets.symmetric(vertical: 7.h),
                                    child: Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        Text(
                                          LocaleKeys.purchase_quantity.tr(),
                                          style: context.typography.vendingBody2B.copyWith(color: mainTextColor),
                                        ),
                                        Text(
                                          '$_selectedQuantity ${LocaleKeys.unit_pcs.tr()}',
                                          style: context.typography.vendingBody1B.copyWith(color: buttonColor),
                                        )
                                      ],
                                    ),
                                  ),
                                  Padding(
                                    padding: EdgeInsets.symmetric(vertical: 7.h),
                                    child: Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        Text(
                                          LocaleKeys.total_payment_amount.tr(),
                                          style: context.typography.vendingBody2B.copyWith(color: mainTextColor),
                                        ),
                                        Text(
                                          '$formattedPrice ${LocaleKeys.currency_won.tr()}',
                                          style: context.typography.vendingBody1B.copyWith(color: buttonColor),
                                        )
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            SizedBox(height: 36.h),
                            // 결제 버튼
                            GestureDetector(
                              onTap: paymentState.isLoading
                                  ? null
                                  : () async {
                                      final isUnderMaintenance = await _checkMaintenance();
                                      if (isUnderMaintenance) return;
                                      _maintenanceTimer?.cancel();
                                      _isCheckingMaintenance = false;
                                      _printJobPollingTimer?.cancel();
                                      ref.read(printQuantityNotifierProvider.notifier).setQuantity(_selectedQuantity);
                                      await ref.read(photoCardPreviewScreenProviderProvider.notifier).payment();
                                      // PrintProcessRouteData().go(context);
                                    },
                              child: Container(
                                width: 804.w,
                                height: 112.h,
                                decoration: BoxDecoration(
                                  color: buttonColor,
                                  borderRadius: BorderRadius.circular(12.r),
                                ),
                                child: Center(
                                  child: paymentState.isLoading
                                      ? SizedBox(
                                          width: 40.r,
                                          height: 40.r,
                                          child: CircularProgressIndicator(
                                            color: buttonTextColor,
                                            strokeWidth: 3.w,
                                          ),
                                        )
                                      : Text(
                                          LocaleKeys.sub02_btn_pay.tr(),
                                          style: context.typography.vendingBtn2B.copyWith(color: buttonTextColor),
                                        ),
                                ),
                              ),
                            ),
                          ],
                        ),
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

  // 수량 버튼 1~10 (키패드 스타일)
  Widget _buildQuantityButton(
    BuildContext context,
    int value,
    Color buttonColor,
    Color mainTextColor,
  ) {
    final isSelected = _selectedQuantity == value;

    return GestureDetector(
      onTap: () => setState(() => _selectedQuantity = value),
      child: Container(
        width: 144.w,
        height: 92.h,
        decoration: BoxDecoration(
            color: isSelected ? buttonColor.withValues(alpha: 0.12) : Colors.white,
            borderRadius: BorderRadius.circular(10.r),
            border: Border.all(
              color: isSelected ? buttonColor : const Color(0xFFE0E0E0),
              width: 2.w,
            ),
            boxShadow: isSelected
                ? [
                    BoxShadow(color: buttonColor, blurRadius: 8, blurStyle: BlurStyle.outer),
                  ]
                : null),
        child: Center(
          child: Text(
            '$value',
            style: context.typography.vendingBtn1B.copyWith(color: isSelected ? buttonColor : mainTextColor),
          ),
        ),
      ),
    );
  }

  // 에러 다이얼로그
  void _showErrorDialog(BuildContext context, String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('결제 실패'),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('확인'),
          ),
        ],
      ),
    );
  }
}
