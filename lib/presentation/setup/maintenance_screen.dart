import 'package:flutter/material.dart';
import 'package:vending_kiosk/core/common/constants/image_paths.dart';
import 'package:vending_kiosk/lib.dart';
import 'package:vending_kiosk/core/ui/widget/triple_tap_fab.dart';

class MaintenanceScreen extends StatelessWidget {
  const MaintenanceScreen({super.key});

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
