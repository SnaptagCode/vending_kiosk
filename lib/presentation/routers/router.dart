import 'package:flutter/material.dart';
import 'package:vending_kiosk/global_shell.dart';
import 'package:vending_kiosk/presentation/setup/kiosk_info_screen.dart';
import 'package:vending_kiosk/presentation/kiosk_shell/kiosk_shell.dart';
import 'package:vending_kiosk/presentation/setup/maintenance_screen.dart';
import 'package:vending_kiosk/presentation/home/card_charging_screen.dart';
import 'package:vending_kiosk/presentation/home/home_screen.dart';
import 'package:vending_kiosk/presentation/setup/payment_history_screen.dart';
import 'package:vending_kiosk/presentation/setup/setup_main_screen.dart';
import 'package:vending_kiosk/presentation/print/print_process_screen.dart';
import 'package:vending_kiosk/presentation/setup/card_dispenser_test_screen.dart';
import 'package:go_router/go_router.dart';

part 'router.g.dart';

final GlobalKey<NavigatorState> rootNavigatorKey = GlobalKey<NavigatorState>();

final GlobalKey<NavigatorState> globalNavigatorKey = GlobalKey<NavigatorState>(debugLabel: 'global');

@TypedShellRoute<GlobalShellRouteData>(
  routes: [
    TypedGoRoute<SetupMainRouteData>(
      path: '/setup',
      routes: [
        TypedGoRoute<KioskInfoRouteData>(path: 'kiosk-info'),
        TypedGoRoute<PaymentHistoryRouteData>(path: 'payment-history'),
        TypedGoRoute<MaintenanceRouteData>(path: 'maintenance'),
        TypedGoRoute<CardDispenserTestRouteData>(path: 'card-dispenser-test'),
      ],
    ),
    TypedGoRoute<KioskRouteData>(
      path: '/kiosk',
      routes: [
        TypedShellRoute<ImageShellRouteData>(
          routes: <TypedRoute<RouteData>>[
            TypedGoRoute<HomeRouteData>(path: 'home'),
            TypedGoRoute<PrintProcessRouteData>(path: 'print-process'),
          ],
        ),
        TypedGoRoute<CardChargingRouteData>(path: 'card-charging'),
      ],
    )
  ],
)
class GlobalShellRouteData extends ShellRouteData {
  const GlobalShellRouteData();

  @override
  Widget builder(BuildContext context, GoRouterState state, Widget navigator) {
    return GlobalShell(child: navigator);
  }
}

class ImageShellRouteData extends ShellRouteData {
  const ImageShellRouteData();

  @override
  Widget builder(BuildContext context, GoRouterState state, Widget navigator) {
    return KioskShell(child: navigator);
  }
}

class SetupMainRouteData extends GoRouteData with _$SetupMainRouteData {
  const SetupMainRouteData();

  @override
  Page<void> buildPage(BuildContext context, GoRouterState state) {
    return NoTransitionPage(
      child: SetupMainScreen(),
    );
  }
}

class PaymentHistoryRouteData extends GoRouteData with _$PaymentHistoryRouteData {
  const PaymentHistoryRouteData();

  @override
  Page<void> buildPage(BuildContext context, GoRouterState state) {
    return NoTransitionPage(
      child: PaymentHistoryScreen(),
    );
  }
}

class KioskInfoRouteData extends GoRouteData with _$KioskInfoRouteData {
  const KioskInfoRouteData();

  @override
  Page<void> buildPage(BuildContext context, GoRouterState state) {
    return NoTransitionPage(
      child: const KioskInfoScreen(),
    );
  }
}

class KioskRouteData extends GoRouteData with _$KioskRouteData {
  const KioskRouteData();

  @override
  Page<void> buildPage(BuildContext context, GoRouterState state) {
    return NoTransitionPage(
      child: SizedBox(),
    );
  }
}

class HomeRouteData extends GoRouteData with _$HomeRouteData {
  const HomeRouteData();

  @override
  Page<void> buildPage(BuildContext context, GoRouterState state) {
    return NoTransitionPage(
      child: HomeScreen(),
    );
  }
}

class PrintProcessRouteData extends GoRouteData with _$PrintProcessRouteData {
  const PrintProcessRouteData();

  @override
  Page<void> buildPage(BuildContext context, GoRouterState state) {
    return NoTransitionPage(
      child: const PrintProcessScreen(),
    );
  }
}

class CardChargingRouteData extends GoRouteData with _$CardChargingRouteData {
  const CardChargingRouteData();

  @override
  Page<void> buildPage(BuildContext context, GoRouterState state) {
    return NoTransitionPage(
      child: const CardChargingScreen(),
    );
  }
}

class MaintenanceRouteData extends GoRouteData with _$MaintenanceRouteData {
  const MaintenanceRouteData();

  @override
  Page<void> buildPage(BuildContext context, GoRouterState state) {
    return NoTransitionPage(
      child: const MaintenanceScreen(),
    );
  }
}

class CardDispenserTestRouteData extends GoRouteData with _$CardDispenserTestRouteData {
  const CardDispenserTestRouteData();

  @override
  Page<void> buildPage(BuildContext context, GoRouterState state) {
    return NoTransitionPage(
      child: const CardDispenserTestScreen(),
    );
  }
}
