import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_snaptag_kiosk/core/common/extensions/build_context.dart';
import 'package:flutter_snaptag_kiosk/core/common/extensions/button_styles.dart';
import 'package:flutter_snaptag_kiosk/core/common/sound/sound_manager.dart';
import 'package:flutter_snaptag_kiosk/core/domain/enums/keypad_mode.dart';
import 'package:flutter_snaptag_kiosk/core/ui/widget/code_keypad.dart';
import 'package:flutter_snaptag_kiosk/locale_keys.dart';

class DialogHelper {
  static Future<bool> showKioskDialog(
    BuildContext context, {
    required String title,
    String? contentText,
    String? cancelButtonText,
    String? confirmButtonText,
  }) async {
    final confirmButtonTextValue = confirmButtonText ?? LocaleKeys.common_btn_back.tr();
    return await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return DefaultTextStyle(
          style: TextStyle(
            fontFamily: context.locale.languageCode == 'ja' ? 'MPLUSRounded' : 'Cafe24Ssurround2',
          ),
          child: AlertDialog(
            backgroundColor: Colors.white,
            insetPadding: EdgeInsets.symmetric(horizontal: 100.h),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20.r),
            ),
            title: Center(
              child: Text(
                title,
                textAlign: TextAlign.center,
                style: context.typography.kioskAlert1B.copyWith(
                  fontFamily: 'Pretendard',
                  color: Colors.black,
                ),
              ),
            ),
            content: contentText != null
                ? Text(
                    contentText,
                    textAlign: TextAlign.center,
                    style: context.typography.kioskAlert2M.copyWith(
                      fontFamily: 'Pretendard',
                      color: Color(0xFF414448),
                    ),
                  )
                : null,
            actions: [
              Row(
                children: [
                  if (cancelButtonText != null)
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () async {
                          await SoundManager().playSound();
                          Navigator.of(context).pop(false);
                        },
                        style: context.refundDialogCancelButtonStyle,
                        child: Text(cancelButtonText, style: TextStyle(color: Color(0xFF999999))),
                      ),
                    ),
                  if (cancelButtonText != null) SizedBox(width: 12.w),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () async {
                        await SoundManager().playSound();
                        Navigator.of(context).pop(true);
                      },
                      style: context.dialogKioskStyle,
                      child: Text(confirmButtonTextValue, style: TextStyle(color: Color(0xFFFFFFFF))),
                    ),
                  ),
                ],
              )
            ],
          ),
        );
      },
    );
  }

  static Future<String?> showKeypadDialog(
    BuildContext context, {
    required ModeType mode,
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

  const _TimeoutDialogWidget({
    required this.title,
    this.message,
    this.messageKey,
    required this.cancelButtonText,
    required this.confirmButtonText,
    this.confirmButtonStyle,
    required this.countdownSeconds,
    required this.onAutoClose,
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
      navigator.pop(true);
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
