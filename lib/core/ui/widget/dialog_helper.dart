import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:vending_kiosk/core/common/extensions/build_context.dart';
import 'package:vending_kiosk/core/common/extensions/button_styles.dart';
import 'package:vending_kiosk/core/common/sound/sound_manager.dart';
import 'package:vending_kiosk/core/data/models/enums/keypad_mode.dart';
import 'package:vending_kiosk/core/ui/widget/code_keypad.dart';
import 'package:vending_kiosk/locale_keys.dart';

class DialogHelper {
  /// 공통 확인/취소 다이얼로그. [showSetupDialog], [showKioskDialog]에서 사용.
  static Future<bool> _showConfirmDialog(
    BuildContext context, {
    required String title,
    String? content,
    bool showCancelButton = false,
    String cancelButtonText = '취소',
    required String confirmButtonText,
    required ButtonStyle cancelButtonStyle,
    required ButtonStyle confirmButtonStyle,
    TextStyle? cancelTextStyle,
    TextStyle? confirmTextStyle,
    bool barrierDismissible = false,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: barrierDismissible,
      builder: (BuildContext dialogContext) {
        final isHwe = context.isHwe;

        return DefaultTextStyle(
          style: TextStyle(
            fontFamily: context.locale.languageCode == 'ja' ? 'MPLUSRounded' : 'Cafe24Ssurround2',
          ),
          child: Dialog(
            backgroundColor: Colors.white,
            insetPadding: EdgeInsets.symmetric(horizontal: 211.w),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20.r),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Padding(
                    padding: EdgeInsets.only(top: 60.h, left: 40.w, right: 40.w),
                    child: Text(
                      title,
                      textAlign: TextAlign.center,
                      style: context.typography.kioskAlert1B.copyWith(
                        fontFamily: isHwe ? 'Hanwha' : 'Pretendard',
                        color: Colors.black,
                        fontSize: isHwe ? 52.sp : 42.sp,
                      ),
                    ),
                  ),
                ),
                if (content != null)
                  Padding(
                    padding: EdgeInsets.only(top: 20.h, left: 40.w, right: 40.w),
                    child: Text(
                      content,
                      textAlign: TextAlign.center,
                      style: context.typography.kioskAlert2M.copyWith(
                        color: Colors.black,
                        fontFamily: 'Pretendard',
                      ),
                    ),
                  ),
                Padding(
                  padding: EdgeInsets.only(top: 36.h, bottom: 40.h, left: 40.w, right: 40.w),
                  child: Row(
                    children: [
                      if (showCancelButton)
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () async {
                              await SoundManager().playSound();
                              Navigator.of(dialogContext).pop(false);
                            },
                            style: cancelButtonStyle,
                            child: Text(cancelButtonText, style: cancelTextStyle),
                          ),
                        ),
                      if (showCancelButton) SizedBox(width: 12.w),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: () async {
                            await SoundManager().playSound();
                            Navigator.of(dialogContext).pop(true);
                          },
                          style: confirmButtonStyle,
                          child: Text(confirmButtonText, style: confirmTextStyle),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
    return result ?? false;
  }

  static Future<void> showPrintCompleteDialog(
    //5초 후 자동으로 닫히고 QR 화면으로 이동
    BuildContext context, {
    VoidCallback? onButtonPressed,
  }) async {
    Future.delayed(const Duration(seconds: 5), () {
      if (!context.mounted) return;
      if (Navigator.of(context, rootNavigator: true).canPop()) {
        Navigator.of(context, rootNavigator: true).pop();
      }
      onButtonPressed?.call();
    });
    final result = await showKioskDialog(
      context,
      title: LocaleKeys.alert_title_print_complete.tr(),
      contentText: LocaleKeys.alert_txt_print_complete.tr(),
      confirmButtonText: LocaleKeys.alert_btn_print_complete.tr(),
    );

    if (result) {
      onButtonPressed?.call();
    }
  }

  static Future<void> showPurchaseFailedDialog(BuildContext context) async {
    await showKioskDialog(
      context,
      title: LocaleKeys.alert_title_purchase_failure.tr(),
      contentText: LocaleKeys.alert_txt_purchase_failure.tr(),
      confirmButtonText: LocaleKeys.alert_btn_purchase_failure.tr(),
    );
  }

  static Future<void> showCardLimitExceededDialog(BuildContext context) async {
    await showKioskDialog(
      context,
      title: LocaleKeys.alert_title_purchase_failure.tr(),
      contentText: LocaleKeys.alert_txt_card_limit_exceeded.tr(),
      confirmButtonText: LocaleKeys.alert_btn_paymentcard_failure.tr(),
    );
  }

  static Future<void> showInsufficientBalanceDialog(BuildContext context) async {
    await showKioskDialog(
      context,
      title: LocaleKeys.alert_title_purchase_failure.tr(),
      contentText: LocaleKeys.alert_txt_insufficient_balance.tr(),
      confirmButtonText: LocaleKeys.alert_btn_paymentcard_failure.tr(),
    );
  }

  static Future<void> showVerificationErrorDialog(BuildContext context) async {
    await showKioskDialog(
      context,
      title: LocaleKeys.alert_title_purchase_failure.tr(),
      contentText: LocaleKeys.alert_txt_verification_error.tr(),
      confirmButtonText: LocaleKeys.alert_btn_paymentcard_failure.tr(),
    );
  }

  static Future<void> showMerchantRestrictionDialog(BuildContext context) async {
    await showKioskDialog(
      context,
      title: LocaleKeys.alert_title_purchase_failure.tr(),
      contentText: LocaleKeys.alert_txt_merchant_restriction.tr(),
      confirmButtonText: LocaleKeys.alert_btn_paymentcard_failure.tr(),
    );
  }

  static Future<void> showTimeoutPaymentDialog(BuildContext context) async {
    await showKioskDialog(
      context,
      title: LocaleKeys.alert_title_purchase_failure.tr(),
      contentText: LocaleKeys.alert_txt_timeout_payment.tr(),
      confirmButtonText: LocaleKeys.alert_btn_paymentcard_failure.tr(),
    );
  }

  static Future<bool> showInsufficientCardStockDialog(BuildContext context) async {
    return await showKioskDialog(
      context,
      title: LocaleKeys.alert_title_insufficient_card_stock.tr(),
      contentText: LocaleKeys.alert_txt_insufficient_card_stock.tr(),
      confirmButtonText: LocaleKeys.alert_btn_ok.tr(),
    );
  }

  // 담당자 문의 알럿
  static Future<bool> showContactManagerDialog(BuildContext context) async {
    return await showKioskDialog(
      context,
      title: LocaleKeys.alert_title_contact_manager.tr(),
      contentText: LocaleKeys.alert_txt_contact_manager.tr(),
      confirmButtonText: LocaleKeys.alert_btn_ok.tr(),
    );
  }

  static Future<void> showAuthNumReissueCompleteDialog(BuildContext context) async {
    await showKioskDialog(
      context,
      title: LocaleKeys.alert_title_authNum_reissue_complete.tr(),
      contentText: LocaleKeys.alert_txt_authNum_reissue_complete.tr(),
      confirmButtonText: LocaleKeys.alert_btn_authNum_reissue_complete.tr(),
    );
  }

  static Future<void> showAuthNumReissueFailureDialog(BuildContext context) async {
    await showKioskDialog(
      context,
      title: LocaleKeys.alert_title_authNum_reissue_failure.tr(),
      contentText: LocaleKeys.alert_txt_authNum_reissue_failure.tr(),
      confirmButtonText: LocaleKeys.alert_btn_authNum_reissue_failure.tr(),
    );
  }

  static Future<bool> showRefundCardInsertDialog(BuildContext context) async {
    return await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (_) => const _RefundCardInsertDialogWidget(),
        ) ??
        false;
  }

  static Future<void> showRefundSuccessDialog(BuildContext context, {required int amount}) async {
    await showKioskDialog(
      context,
      title: '환불 완료',
      contentText: '$amount원이 환불되었습니다.',
      confirmButtonText: '확인',
    );
  }

  static Future<void> showRefundFailedDialog(BuildContext context, {required String reason}) async {
    await showKioskDialog(
      context,
      title: '환불 실패',
      contentText: reason,
      confirmButtonText: '확인',
    );
  }

  static Future<bool> showSetupDialog(
    BuildContext context, {
    required String title,
    String? content,
    bool showCancelButton = false,
    String cancelButtonText = '취소',
    String confirmButtonText = '확인',
  }) async {
    return await _showConfirmDialog(
      context,
      title: title,
      content: content,
      showCancelButton: showCancelButton,
      cancelButtonText: cancelButtonText,
      confirmButtonText: confirmButtonText,
      cancelButtonStyle: context.setupDialogCancelButtonStyle,
      confirmButtonStyle: context.setupDialogConfirmButtonStyle,
    );
  }

  static Future<bool> showKioskDialog(
    BuildContext context, {
    required String title,
    required String contentText,
    String? cancelButtonText,
    required String confirmButtonText,
    ButtonStyle? confirmButtonStyle,
    bool barrierDismissible = false,
  }) async {
    return await _showConfirmDialog(
      context,
      title: title,
      content: contentText,
      showCancelButton: cancelButtonText != null,
      cancelButtonText: cancelButtonText ?? '취소',
      confirmButtonText: confirmButtonText,
      cancelButtonStyle: context.refundDialogCancelButtonStyle,
      confirmButtonStyle: confirmButtonStyle ?? context.dialogKioskStyle,
      cancelTextStyle: const TextStyle(color: Color(0xFF999999)),
      confirmTextStyle: const TextStyle(color: Color(0xFFFFFFFF)),
      barrierDismissible: barrierDismissible,
    );
  }

  /// 카드 추가 다이얼로그 (수량 입력 필드 + 취소/확인)
  static Future<int?> showCardAddDialog(
    BuildContext context, {
    required int cardCapacity,
  }) async {
    int? enteredValue;

    return await showDialog<int>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setState) {
            return DefaultTextStyle(
              style: TextStyle(
                fontFamily: context.locale.languageCode == 'ja'
                    ? 'MPLUSRounded'
                    : 'Cafe24Ssurround2',
              ),
              child: Dialog(
                backgroundColor: Colors.white,
                insetPadding: EdgeInsets.symmetric(horizontal: 211.w),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20.r)),
                child: Padding(
                  padding: EdgeInsets.fromLTRB(40.w, 60.h, 40.w, 40.h),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        '카드 추가',
                        textAlign: TextAlign.center,
                        style: context.typography.kioskAlert1B.copyWith(
                            fontFamily: 'Pretendard', color: Colors.black),
                      ),
                      SizedBox(height: 20.h),
                      Text(
                        '추가 카드 수량 (최대 $cardCapacity장까지 추가 가능)',
                        textAlign: TextAlign.center,
                        style: context.typography.kioskAlert2M.copyWith(
                            fontFamily: 'Pretendard', color: Colors.black),
                      ),
                      SizedBox(height: 20.h),
                      InkWell(
                        onTap: () async {
                          final value = await DialogHelper.showKeypadDialog(
                              context, mode: ModeType.card);
                          if (value == null || value.isEmpty) return;
                          setState(() => enteredValue = int.tryParse(value));
                        },
                        borderRadius: BorderRadius.circular(12),
                        child: Container(
                          height: 80.h,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            border: Border.all(color: Colors.black),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          alignment: Alignment.centerRight,
                          padding: EdgeInsets.symmetric(horizontal: 20.w),
                          child: Text(
                            enteredValue != null ? '$enteredValue 장' : '',
                            style: context.typography.kioskBody2B
                                .copyWith(color: Colors.black),
                          ),
                        ),
                      ),
                      SizedBox(height: 36.h),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: () =>
                                  Navigator.of(dialogContext).pop(null),
                              style: context.setupDialogCancelButtonStyle,
                              child: const Text('취소'),
                            ),
                          ),
                          SizedBox(width: 12.w),
                          Expanded(
                            child: ElevatedButton(
                              onPressed: enteredValue == null
                                  ? null
                                  : () async {
                                      await SoundManager().playSound();
                                      if (!dialogContext.mounted) return;
                                      Navigator.of(dialogContext)
                                          .pop(enteredValue);
                                    },
                              style: context.setupDialogConfirmButtonStyle,
                              child: const Text('확인'),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  static Future<String?> showKeypadDialog(
    BuildContext context, {
    required ModeType mode,
    String initialValue = '',
  }) async {
    return await showDialog<String>(
      context: context,
      barrierDismissible: true,
      builder: (BuildContext context) {
        return DefaultTextStyle(
          style: TextStyle(
            fontFamily: context.locale.languageCode == 'ja' ? 'MPLUSRounded' : 'Cafe24Ssurround2',
          ),
          child: AlertDialog(
            backgroundColor: Colors.white,
            insetPadding: EdgeInsets.symmetric(horizontal: 100.w),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20.r),
            ),
            content: SizedBox(
              width: 418.w,
              height: 600.h,
              child: AuthCodeKeypad(
                mode: mode,
                initialValue: initialValue,
                onCompleted: (code) {
                  print("입력된 코드: $code");
                  Navigator.pop(context, code);
                },
              ),
            ),
          ),
        );
      },
    );
  }

  /// 타임아웃 알럿 (실시간 카운트다운 표시)
  static Future<bool> showTimeoutDialog(
    BuildContext context,
    ButtonStyle? confirmButtonStyle, {
    required String title,
    String? message,
    String? messageKey,
    required String cancelButtonText,
    required String confirmButtonText,
    required int countdownSeconds,
    required VoidCallback onAutoClose,
    bool autoCloseResult = true,
  }) async {
    return await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext dialogContext) {
        return _TimeoutDialogWidget(
          title: title,
          message: message,
          messageKey: messageKey,
          cancelButtonText: cancelButtonText,
          confirmButtonText: confirmButtonText,
          confirmButtonStyle: confirmButtonStyle,
          countdownSeconds: countdownSeconds,
          onAutoClose: onAutoClose,
          autoCloseResult: autoCloseResult,
        );
      },
    );
  }
}

/// 타임아웃 다이얼로그 위젯 (실시간 카운트다운)
class _TimeoutDialogWidget extends StatefulWidget {
  final String title;
  final String? message;
  final String? messageKey;
  final String cancelButtonText;
  final String confirmButtonText;
  final ButtonStyle? confirmButtonStyle;
  final int countdownSeconds;
  final VoidCallback onAutoClose;
  final bool autoCloseResult;

  const _TimeoutDialogWidget({
    required this.title,
    this.message,
    this.messageKey,
    required this.cancelButtonText,
    required this.confirmButtonText,
    this.confirmButtonStyle,
    required this.countdownSeconds,
    required this.onAutoClose,
    this.autoCloseResult = true,
  });

  @override
  State<_TimeoutDialogWidget> createState() => _TimeoutDialogWidgetState();
}

class _TimeoutDialogWidgetState extends State<_TimeoutDialogWidget> {
  late int _remainingSeconds;
  Timer? _countdownTimer;
  Timer? _autoCloseTimer;

  @override
  void initState() {
    super.initState();
    _remainingSeconds = widget.countdownSeconds;

    // 1초마다 카운트다운 업데이트
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) {
        setState(() {
          if (_remainingSeconds > 0) {
            _remainingSeconds--;
          } else {
            timer.cancel();
          }
        });
      } else {
        timer.cancel();
      }
    });

    // 자동으로 닫기
    _autoCloseTimer = Timer(Duration(seconds: widget.countdownSeconds), () {
      if (!mounted) return;

      final navigator = Navigator.of(context, rootNavigator: true);

      widget.onAutoClose();
      navigator.pop(widget.autoCloseResult);
    });
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    _autoCloseTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // showTwoButtonKioskDialog와 동일한 구조 사용
    return DefaultTextStyle(
      style: TextStyle(
        fontFamily: context.locale.languageCode == 'ja' ? 'MPLUSRounded' : 'Cafe24Ssurround2',
      ),
      child: AlertDialog(
        backgroundColor: Colors.white,
        insetPadding: EdgeInsets.symmetric(horizontal: 100.w),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20.r),
        ),
        titlePadding: EdgeInsets.zero,
        contentPadding: EdgeInsets.zero,
        actionsPadding: EdgeInsets.zero,
        title: Center(
          child: Padding(
            padding: EdgeInsets.only(top: 60.h, bottom: 20.h, left: 40.w, right: 40.w),
            child: Text(
              widget.title,
              textAlign: TextAlign.center,
              style: context.typography.kioskAlert1B.copyWith(
                fontFamily: 'Pretendard',
                color: Colors.black,
              ),
            ),
          ),
        ),
        content: Padding(
          padding: EdgeInsets.only(left: 40.w, right: 40.w),
          child: Text(
            widget.messageKey != null
                ? widget.messageKey!.tr().replaceAll('{}', '$_remainingSeconds')
                : (widget.message?.replaceAll('{}', '$_remainingSeconds') ?? ''),
            textAlign: TextAlign.center,
            style: context.typography.kioskAlert2M.copyWith(
              fontFamily: 'Pretendard',
              color: Color(0xFF414448),
            ),
          ),
        ),
        actions: [
          Padding(
            padding: EdgeInsets.only(bottom: 40.h, top: 36.h, left: 40.w, right: 40.w),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () async {
                      await SoundManager().playSound();
                      Navigator.of(context).pop(false);
                    },
                    style: context.refundDialogCancelButtonStyle,
                    child: Text(widget.cancelButtonText, style: TextStyle(color: Color(0xFF999999))),
                  ),
                ),
                SizedBox(width: 12.w),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () async {
                      await SoundManager().playSound();
                      Navigator.of(context).pop(true);
                    },
                    style: widget.confirmButtonStyle ?? context.refundDialogConfirmButtonStyle,
                    child: Text(widget.confirmButtonText, style: TextStyle(color: Color(0xFFFFFFFF))),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _RefundCardInsertDialogWidget extends StatefulWidget {
  const _RefundCardInsertDialogWidget();

  @override
  State<_RefundCardInsertDialogWidget> createState() => _RefundCardInsertDialogWidgetState();
}

class _RefundCardInsertDialogWidgetState extends State<_RefundCardInsertDialogWidget> {
  static const int _totalSeconds = 30;
  late int _remainingSeconds;
  Timer? _countdownTimer;
  Timer? _autoCloseTimer;

  @override
  void initState() {
    super.initState();
    _remainingSeconds = _totalSeconds;
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _remainingSeconds = (_remainingSeconds - 1).clamp(0, _totalSeconds));
    });
    _autoCloseTimer = Timer(const Duration(seconds: _totalSeconds), () {
      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).pop(false);
    });
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    _autoCloseTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isHwe = context.isHwe;
    return DefaultTextStyle(
      style: TextStyle(
        fontFamily: context.locale.languageCode == 'ja' ? 'MPLUSRounded' : 'Cafe24Ssurround2',
      ),
      child: Dialog(
        backgroundColor: Colors.white,
        insetPadding: EdgeInsets.symmetric(horizontal: 211.w),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20.r)),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Padding(
                padding: EdgeInsets.only(top: 60.h, left: 40.w, right: 40.w),
                child: Text(
                  '환불을 진행합니다',
                  textAlign: TextAlign.center,
                  style: context.typography.kioskAlert1B.copyWith(
                    fontFamily: isHwe ? 'Hanwha' : 'Pretendard',
                    color: Colors.black,
                    fontSize: isHwe ? 52.sp : 42.sp,
                  ),
                ),
              ),
            ),
            Padding(
              padding: EdgeInsets.only(top: 20.h, left: 40.w, right: 40.w),
              child: Text(
                '카드를 삽입한 후 확인을 눌러주세요.\n($_remainingSeconds초 후 자동 취소)',
                textAlign: TextAlign.center,
                style: context.typography.kioskAlert2M.copyWith(
                  color: Colors.black,
                  fontFamily: 'Pretendard',
                ),
              ),
            ),
            Padding(
              padding: EdgeInsets.only(top: 36.h, bottom: 40.h, left: 40.w, right: 40.w),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () async {
                        await SoundManager().playSound();
                        if (mounted) Navigator.of(context, rootNavigator: true).pop(false);
                      },
                      style: context.refundDialogCancelButtonStyle,
                      child: const Text('취소', style: TextStyle(color: Color(0xFF999999))),
                    ),
                  ),
                  SizedBox(width: 12.w),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () async {
                        await SoundManager().playSound();
                        if (mounted) Navigator.of(context, rootNavigator: true).pop(true);
                      },
                      style: context.dialogKioskStyle,
                      child: const Text('확인', style: TextStyle(color: Color(0xFFFFFFFF))),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
