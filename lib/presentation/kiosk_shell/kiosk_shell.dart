import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:vending_kiosk/core/common/logger/slack_log_service.dart';
import 'package:vending_kiosk/core/ui/widget/back_button.dart';
import 'package:vending_kiosk/core/ui/widget/kiosk_navigator_button.dart';
import 'package:vending_kiosk/core/ui/widget/printer_status_badge.dart';
import 'package:vending_kiosk/core/ui/widget/triple_tap_fab.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:vending_kiosk/locale_keys.dart';
import 'package:vending_kiosk/presentation/home/maintenance_provider.dart';
import 'package:vending_kiosk/presentation/kiosk_shell/kiosk_info_service.dart';
import 'package:loader_overlay/loader_overlay.dart';

class KioskShell extends ConsumerStatefulWidget {
  final Widget child;

  const KioskShell({super.key, required this.child});

  @override
  ConsumerState<KioskShell> createState() => _KioskShellState();
}

class _KioskShellState extends ConsumerState<KioskShell> {
  Timer? _periodicTimer;
  bool _hasNetworkError = false;

  @override
  void initState() {
    super.initState();

    // _periodicTimer = Timer.periodic(const Duration(minutes: 30), (timer) {
    //   SlackLogService().sendPeriodicLogBroadcastLogToSlack();
    // });
  }

  @override
  void dispose() {
    _periodicTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // maintenanceStateProvider가 false가 되면 에러 메시지 초기화
    ref.listen(maintenanceStateProvider, (_, next) {
      if (!next) {
        ref.read(maintenanceErrorProvider.notifier).state = false;
      }
    });

    final settings = ref.read(kioskInfoServiceProvider);

    return Stack(
      children: [
        Scaffold(
          body: Column(
            children: [
              SizedBox(
                height: 855.h,
                width: double.infinity,
                child: Image.network(
                  settings?.topBannerUrl ?? '',
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) {
                    return const Center(child: Text('이미지를 찾을 수 없습니다.'));
                  },
                ),
              ),
              Expanded(
                child: LoaderOverlay(
                  overlayWidgetBuilder: (_) => Center(
                    child: SizedBox(
                      width: 350.h,
                      height: 350.h,
                      child: CircularProgressIndicator(strokeWidth: 15.h),
                    ),
                  ),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      image: !_hasNetworkError
                          ? DecorationImage(
                              image: NetworkImage(settings?.mainImageUrl ?? ''),
                              onError: (_, __) {
                                if (mounted) {
                                  setState(() {
                                    _hasNetworkError = true;
                                  });
                                }
                              },
                              fit: BoxFit.cover,
                            )
                          : const DecorationImage(
                              image: AssetImage('assets/images/fallback_body.jpg'),
                              fit: BoxFit.cover,
                            ),
                    ),
                    child: Column(
                      children: [
                        SizedBox(
                          height: 70.h,
                          child: Row(
                            children: [
                              SizedBox(width: 30.w),
                              KioskBackButton(),
                              const Spacer(),
                              KioskNavigatorButton(),
                              SizedBox(width: 80.w),
                            ],
                          ),
                        ),
                        Expanded(
                          child: SizedBox.expand(child: widget.child),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
          floatingActionButtonLocation: FloatingActionButtonLocation.endTop,
          floatingActionButton: TripleTapFloatingButton(),
        ),
        if (ref.watch(maintenanceStateProvider))
          Positioned.fill(
            child: Container(
              color: const Color(0xB3000000),
              child: Stack(
                children: [
                  SizedBox.expand(
                    child: Builder(
                      builder: (context) {
                        final isError = ref.watch(maintenanceErrorProvider);
                        return Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              isError ? Icons.error_outline : Icons.credit_card,
                              color: Colors.white,
                              size: 64,
                            ),
                            const SizedBox(height: 24),
                            Text(
                              isError
                                  ? LocaleKeys.alert_txt_contact_manager.tr()
                                  : LocaleKeys.maintenance_txt_card_charging.tr(),
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 42.sp,
                                fontWeight: FontWeight.w600,
                                height: 1.5,
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                  const Align(
                    alignment: Alignment.topRight,
                    child: TripleTapFloatingButton(),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
