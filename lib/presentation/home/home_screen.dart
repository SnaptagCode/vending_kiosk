import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:vending_kiosk/core/common/extensions/build_context.dart';
import 'package:vending_kiosk/core/ui/widget/dialog_helper.dart';
import 'package:vending_kiosk/locale_keys.dart';
import 'package:vending_kiosk/presentation/home/payment_provider.dart';
import 'package:vending_kiosk/presentation/home/quantity_provider.dart';
import 'package:vending_kiosk/presentation/kiosk_shell/home_timeout_provider.dart';
import 'package:vending_kiosk/presentation/kiosk_shell/kiosk_info_service.dart';
import 'package:vending_kiosk/presentation/payment/payment_failed_type.dart';
import 'package:vending_kiosk/presentation/payment/photo_card_preview_screen_provider.dart';
import 'package:vending_kiosk/presentation/routers/router.dart';
import 'package:loader_overlay/loader_overlay.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  @override
  void initState() {
    super.initState();
    // 화면 진입 시 수량 초기화
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(quantityProvider.notifier).reset();
      ref.read(paymentNotifierProvider.notifier).reset();
    });
  }

  @override
  Widget build(BuildContext context) {
    final kiosk = ref.watch(kioskInfoServiceProvider);
    final quantity = ref.watch(quantityProvider);
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
              '사진 카드 주문',
              style: context.typography.kioskBtn1B.copyWith(
                fontSize: 60.sp,
                color: mainTextColor,
              ),
            ),
            SizedBox(height: 60.h),

            // 수량 선택 컨테이너
            Container(
              width: 800.w,
              padding: EdgeInsets.all(40.r),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.1),
                borderRadius: BorderRadius.circular(30.r),
                border: Border.all(
                  color: Colors.white.withOpacity(0.3),
                  width: 2.w,
                ),
              ),
              child: Column(
                children: [
                  // 수량 라벨
                  Text(
                    '수량 선택',
                    style: context.typography.kioskBtn1B.copyWith(
                      fontSize: 40.sp,
                      color: mainTextColor,
                    ),
                  ),
                  SizedBox(height: 30.h),

                  // 빠른 선택 버튼들 (1, 5, 10)
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _buildQuickSelectButton(context, 1, buttonColor, buttonTextColor),
                      SizedBox(width: 20.w),
                      _buildQuickSelectButton(context, 5, buttonColor, buttonTextColor),
                      SizedBox(width: 20.w),
                      _buildQuickSelectButton(context, 10, buttonColor, buttonTextColor),
                    ],
                  ),
                  SizedBox(height: 40.h),

                  // 수량 조정 영역
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // - 버튼
                      _buildAdjustButton(
                        context,
                        icon: Icons.remove,
                        onTap: () => ref.read(quantityProvider.notifier).decrement(),
                        buttonColor: buttonColor,
                        buttonTextColor: buttonTextColor,
                      ),

                      // 현재 수량 표시
                      Container(
                        width: 200.w,
                        margin: EdgeInsets.symmetric(horizontal: 20.w),
                        padding: EdgeInsets.symmetric(vertical: 20.h),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(15.r),
                        ),
                        child: Text(
                          '$quantity',
                          style: TextStyle(
                            fontSize: 60.sp,
                            fontWeight: FontWeight.bold,
                            color: Colors.black,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),

                      // + 버튼
                      _buildAdjustButton(
                        context,
                        icon: Icons.add,
                        onTap: () => ref.read(quantityProvider.notifier).increment(),
                        buttonColor: buttonColor,
                        buttonTextColor: buttonTextColor,
                      ),
                    ],
                  ),
                  SizedBox(height: 40.h),

                  // 가격 표시
                  Container(
                    padding: EdgeInsets.symmetric(horizontal: 40.w, vertical: 20.h),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(15.r),
                    ),
                    child: Column(
                      children: [
                        Text(
                          '단가: ${NumberFormat.currency(locale: 'ko_KR', symbol: '').format(unitPrice)}${LocaleKeys.currency_won.tr()}',
                          style: TextStyle(
                            fontSize: 28.sp,
                            color: mainTextColor.withOpacity(0.8),
                          ),
                        ),
                        SizedBox(height: 10.h),
                        Text(
                          '합계: $formattedPrice${LocaleKeys.currency_won.tr()}',
                          style: TextStyle(
                            fontSize: 40.sp,
                            fontWeight: FontWeight.bold,
                            color: mainTextColor,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(height: 60.h),

            // 결제 버튼
            GestureDetector(
              onTap: paymentState.isLoading
                  ? null
                  : () async {
                      await ref.read(photoCardPreviewScreenProviderProvider.notifier).payment();
                    },
              child: Container(
                width: 600.w,
                height: 100.h,
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
                            fontSize: 45.sp,
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

  // 빠른 선택 버튼 (1, 5, 10)
  Widget _buildQuickSelectButton(
    BuildContext context,
    int value,
    Color buttonColor,
    Color buttonTextColor,
  ) {
    final isSelected = ref.watch(quantityProvider) == value;

    return GestureDetector(
      onTap: () => ref.read(quantityProvider.notifier).setQuantity(value),
      child: Container(
        width: 150.w,
        height: 80.h,
        decoration: BoxDecoration(
          color: isSelected ? buttonColor : Colors.white.withOpacity(0.2),
          borderRadius: BorderRadius.circular(15.r),
          border: Border.all(
            color: isSelected ? buttonColor : Colors.white.withOpacity(0.5),
            width: 2.w,
          ),
        ),
        child: Center(
          child: Text(
            '$value',
            style: TextStyle(
              fontSize: 40.sp,
              fontWeight: FontWeight.bold,
              color: isSelected ? buttonTextColor : Colors.white,
            ),
          ),
        ),
      ),
    );
  }

  // +/- 조정 버튼
  Widget _buildAdjustButton(
    BuildContext context, {
    required IconData icon,
    required VoidCallback onTap,
    required Color buttonColor,
    required Color buttonTextColor,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 100.r,
        height: 100.r,
        decoration: BoxDecoration(
          color: buttonColor,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.2),
              blurRadius: 8,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Icon(
          icon,
          size: 50.sp,
          color: buttonTextColor,
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
