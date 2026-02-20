import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:vending_kiosk/core/common/extensions/build_context.dart';
import 'package:vending_kiosk/core/ui/widget/dialog_helper.dart';
import 'package:vending_kiosk/locale_keys.dart';
import 'package:vending_kiosk/presentation/home/payment_provider.dart';
import 'package:vending_kiosk/presentation/home/print_quantity_provider.dart';
import 'package:vending_kiosk/presentation/kiosk_shell/home_timeout_provider.dart';
import 'package:vending_kiosk/presentation/kiosk_shell/kiosk_info_service.dart';
import 'package:vending_kiosk/presentation/home/payment/payment_failed_type.dart';
import 'package:vending_kiosk/presentation/home/payment/photo_card_preview_screen_provider.dart';
import 'package:vending_kiosk/presentation/routers/router.dart';
import 'package:loader_overlay/loader_overlay.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  // late final FlutterTts _flutterTts;
  // Timer? _ttsTimer;

  @override
  void initState() {
    super.initState();
    // _initializeTts();
  }

  @override
  void dispose() {
    // _ttsTimer?.cancel();
    // _flutterTts.stop();
    super.dispose();
  }

  // ㅌ

  @override
  Widget build(BuildContext context) {
    final kiosk = ref.watch(kioskInfoServiceProvider);
    final quantity = ref.watch(printQuantityProvider);
    final paymentState = ref.watch(paymentNotifierProvider);

    // 가격 계산
    final unitPrice = kiosk?.photoCardPrice ?? 1000;
    final totalPrice = unitPrice * quantity;
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
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // 타이틀
            Text(
              '구매 수량을 선택해 주세요.',
              style: context.typography.kioskBtn1B.copyWith(
                fontSize: 53.sp,
                color: mainTextColor,
              ),
            ),
            SizedBox(height: 42.h),

            // 수량 선택 컨테이너
            Column(
              children: [
                // 수량 버튼 1~10 (2행)
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        for (int i = 1; i <= 5; i++) ...[
                          if (i > 1) SizedBox(width: 16.w),
                          _buildQuantityButton(context, i, buttonColor, buttonTextColor),
                        ],
                      ],
                    ),
                    SizedBox(height: 16.h),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        for (int i = 6; i <= 10; i++) ...[
                          if (i > 6) SizedBox(width: 16.w),
                          _buildQuantityButton(context, i, buttonColor, buttonTextColor),
                        ],
                      ],
                    ),
                  ],
                ),
                SizedBox(height: 42.h),

                // 가격 표시
                Container(
                  padding: EdgeInsets.symmetric(horizontal: 30.w, vertical: 32.h),
                  width: 789.w,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(15.r),
                  ),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            '구매 수량',
                            style: TextStyle(
                              fontSize: 18.sp,
                              color: Colors.grey,
                            ),
                          ),
                          Text(
                            '$quantity',
                            style: TextStyle(
                              fontSize: 18.sp,
                              color: mainTextColor,
                            ),
                          )
                        ],
                      ),
                      SizedBox(height: 15.h),
                      Divider(
                        color: Colors.grey,
                        height: 1.h,
                      ),
                      SizedBox(height: 15.h),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            '총 금액',
                            style: TextStyle(
                              fontSize: 20.sp,
                              color: buttonColor,
                            ),
                          ),
                          Text(
                            '$formattedPrice${LocaleKeys.currency_won.tr()}',
                            style: TextStyle(
                              fontSize: 18.sp,
                              color: mainTextColor,
                            ),
                          )
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
            SizedBox(height: 40.h),
            // 결제 버튼
            GestureDetector(
              onTap: paymentState.isLoading
                  ? null
                  : () async {
                      await ref.read(photoCardPreviewScreenProviderProvider.notifier).payment();
                      // 결제 성공 시 출력 화면으로 이동
                      // PrintProcessRouteData().go(context);
                    },
              child: Container(
                width: 789.w,
                height: 92.h,
                decoration: BoxDecoration(
                  color: buttonColor,
                  borderRadius: BorderRadius.circular(20.r),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.3),
                      blurRadius: 10,
                      offset: const Offset(0, 5),
                    ),
                  ],
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
                          style: context.typography.kioskBtn1B.copyWith(
                            fontSize: 34.sp,
                            color: buttonTextColor,
                          ),
                        ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // 수량 버튼 1~10 (선택: 흰색, 미선택: mainButtonColor)
  Widget _buildQuantityButton(
    BuildContext context,
    int value,
    Color buttonColor,
    Color buttonTextColor,
  ) {
    final isSelected = ref.watch(printQuantityProvider) == value;

    return GestureDetector(
      onTap: () => ref.read(printQuantityProvider.notifier).setQuantity(value),
      child: Container(
        width: 145.w,
        height: 77.h,
        decoration: BoxDecoration(
          color: isSelected ? Colors.white : buttonColor,
          borderRadius: BorderRadius.circular(15.r),
          border: Border.all(
            color: isSelected ? Colors.white : buttonColor,
            width: 2.w,
          ),
        ),
        child: Center(
          child: Text(
            '$value',
            style: TextStyle(
              fontSize: 36.sp,
              fontWeight: FontWeight.bold,
              color: isSelected ? buttonColor : buttonTextColor,
            ),
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
