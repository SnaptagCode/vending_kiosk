import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vending_kiosk/core/common/constants/image_paths.dart';
import 'package:vending_kiosk/core/data/repositories/kiosk_repository.dart';
import 'package:vending_kiosk/core/ui/widget/triple_tap_fab.dart';
import 'package:vending_kiosk/presentation/kiosk_shell/kiosk_info_service.dart';
import 'package:vending_kiosk/presentation/routers/router.dart';
import 'package:vending_kiosk/presentation/setup/uuid_provider.dart';

class CardChargingScreen extends ConsumerStatefulWidget {
  const CardChargingScreen({super.key});

  @override
  ConsumerState<CardChargingScreen> createState() => _CardChargingScreenState();
}

class _CardChargingScreenState extends ConsumerState<CardChargingScreen> {
  Timer? _pollingTimer;

  @override
  void initState() {
    super.initState();
    _startPolling();
  }

  @override
  void dispose() {
    _pollingTimer?.cancel();
    super.dispose();
  }

  void _startPolling() {
    _pollingTimer = Timer.periodic(const Duration(seconds: 1), (_) async {
      await _checkMaintenance();
    });
  }

  Future<void> _checkMaintenance() async {
    try {
      final kioskInfo = ref.read(kioskInfoServiceProvider);
      if (kioskInfo == null) return;

      final uniqueKey = await ref.read(deviceUuidProvider.future);
      final response = await ref.read(kioskRepositoryProvider).getMachineMaintenance(
            machineId: kioskInfo.kioskMachineId,
            uniqueKey: uniqueKey,
          );

      if (!response.isUnderMaintenance && mounted) {
        _pollingTimer?.cancel();
        HomeRouteData().go(context);
      }
    } catch (_) {
      // 에러 발생 시 계속 폴링
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SizedBox.expand(
        child: Image.asset(
          SnaptagImages.maintenance,
          fit: BoxFit.contain,
        ),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.endTop,
      floatingActionButton: TripleTapFloatingButton(),
    );
  }
}
