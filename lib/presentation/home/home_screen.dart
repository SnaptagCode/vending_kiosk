import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:vending_kiosk/core/common/extensions/build_context.dart';
import 'package:vending_kiosk/core/data/repositories/kiosk_repository.dart';
import 'package:vending_kiosk/core/ui/widget/dialog_helper.dart';
import 'package:vending_kiosk/locale_keys.dart';
import 'package:vending_kiosk/presentation/home/payment_provider.dart';
import 'package:vending_kiosk/presentation/home/print_quantity_provider.dart';
import 'package:vending_kiosk/presentation/kiosk_shell/home_timeout_provider.dart';
import 'package:vending_kiosk/presentation/kiosk_shell/kiosk_info_service.dart';
import 'package:vending_kiosk/presentation/home/payment/payment_failed_type.dart';
import 'package:vending_kiosk/presentation/home/payment/photo_card_preview_screen_provider.dart';
import 'package:vending_kiosk/presentation/routers/router.dart';
import 'package:vending_kiosk/presentation/setup/uuid_provider.dart';
import 'package:loader_overlay/loader_overlay.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  Timer? _maintenanceTimer;

  @override
  void initState() {
    super.initState();

    // _startMaintenancePolling();
  }

  @override
  void dispose() {
    _maintenanceTimer?.cancel();
    super.dispose();
  }

  void _startMaintenancePolling() {
    _maintenanceTimer = Timer.periodic(const Duration(seconds: 3), (_) async {
      await _checkMaintenance();
    });
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

      if (response.isUnderMaintenance && mounted) {
        _maintenanceTimer?.cancel();
        CardChargingRouteData().go(context);
        return true;
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final kiosk = ref.watch(kioskInfoServiceProvider);
    final quantity = ref.watch(printQuantityNotifierProvider);
    final paymentState = ref.watch(paymentNotifierProvider);

    // 가격 계산
    final unitPrice = kiosk?.photoCardPrice ?? 1000;
    final totalPrice = unitPrice * quantity.total;
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

            if (error is PaymentFailedException) {
              if (error is InsufficientCardStockException) {
                await DialogHelper.showInsufficientCardStockDialog(
                  context,
                  requestedQuantity: error.requestedQuantity,
                  availableStock: error.availableStock,
                );
                return;
              }
              if (error is TimeoutPaymentException) {
                await DialogHelper.showTimeoutPaymentDialog(
                  context,
                );
                return;
              }
              if (error.description?.contains('한도') ?? false) {
                await DialogHelper.showCardLimitExceededDialog(
                  context,
                );
                return;
              }
              if (error.description?.contains('잔액') ?? false) {
                await DialogHelper.showInsufficientBalanceDialog(
                  context,
                );
                return;
              }
              if (error.description?.contains('인증') ?? false) {
                await DialogHelper.showVerificationErrorDialog(
                  context,
                );
                return;
              }
              if (error.description?.contains('가맹점') ?? false) {
                await DialogHelper.showMerchantRestrictionDialog(
                  context,
                );
                return;
              }
            }

            await DialogHelper.showPurchaseFailedDialog(
              context,
            );
            return;
          },
          loading: () => null,
          data: (_) async {
            // 결제 성공 시 출력 화면으로 이동
            PrintProcessRouteData().go(context);
          },
        );
      },
    );

    final buttonColor = kiosk?.mainButtonColor != null
        ? Color(int.parse(kiosk!.mainButtonColor.replaceFirst('#', '0xff')))
        : const Color(0xFF4CAF50);

    final buttonTextColor = kiosk?.buttonTextColor != null
        ? Color(int.parse(kiosk!.buttonTextColor.replaceFirst('#', '0xff')))
        : Colors.white;

    final mainTextColor =
        kiosk?.mainTextColor != null ? Color(int.parse(kiosk!.mainTextColor.replaceFirst('#', '0xff'))) : Colors.white;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Center(
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 80.w),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // 카드 1: 타이틀 + 수량 선택 키패드
              Container(
                width: double.infinity,
                padding: EdgeInsets.fromLTRB(58.w, 52.h, 58.w, 34.h),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.only(
                      topLeft: Radius.circular(12.r),
                      topRight: Radius.circular(12.r),
                      bottomLeft: Radius.circular(0.r),
                      bottomRight: Radius.circular(0.r)),
                ),
                child: Column(
                  children: [
                    // 타이틀
                    Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(
                            text: '구매 수량',
                            style: context.typography.vendingTitle2B.copyWith(
                              color: buttonColor,
                            ),
                          ),
                          TextSpan(
                            text: '을 선택해 주세요.',
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

              // 카드 사이 간격 (배경이 보이는 구분선 역할)
              SizedBox(height: 12.h),

              // 카드 2: 가격 표시 + 결제 버튼
              Container(
                width: double.infinity,
                padding: EdgeInsets.fromLTRB(58.w, 40.h, 58.w, 34.h),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.only(
                      topLeft: Radius.circular(0.r),
                      topRight: Radius.circular(0.r),
                      bottomLeft: Radius.circular(12.r),
                      bottomRight: Radius.circular(12.r)),
                ),
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
                                  '구매 수량',
                                  style: context.typography.vendingBody2B.copyWith(color: const Color(0xFF888888)),
                                ),
                                Text(
                                  '${quantity.total} 장',
                                  style: context.typography.vendingBody1B.copyWith(color: buttonColor),
                                )
                              ],
                            ),
                          ),
                          SizedBox(height: 4.h),
                          Padding(
                            padding: EdgeInsets.symmetric(vertical: 7.h),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  '총 결제금액',
                                  style: context.typography.vendingBody2B.copyWith(color: const Color(0xFF888888)),
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
                                  '결제하기',
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
    );
  }

  // 수량 버튼 1~10 (키패드 스타일)
  Widget _buildQuantityButton(
    BuildContext context,
    int value,
    Color buttonColor,
    Color mainTextColor,
  ) {
    final isSelected = ref.watch(printQuantityNotifierProvider).total == value;

    return GestureDetector(
      onTap: () => ref.read(printQuantityNotifierProvider.notifier).setQuantity(value),
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
