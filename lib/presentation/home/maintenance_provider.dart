import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 점검 중 여부를 전역으로 공유하는 provider.
/// HomeScreen에서 폴링 후 업데이트, KioskShell에서 오버레이 표시에 사용.
final maintenanceStateProvider = StateProvider<bool>((ref) => false);
