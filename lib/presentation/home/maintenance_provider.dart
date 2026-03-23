import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 점검 중 여부를 전역으로 공유하는 provider.
/// HomeScreen에서 폴링 후 업데이트, KioskShell에서 오버레이 표시에 사용.
final maintenanceStateProvider = StateProvider<bool>((ref) => false);

/// 카드 배출기 예외 발생 시 오버레이 워딩 변경용 provider.
/// true이면 에러 워딩, false이면 기본 워딩("카드 충전중").
/// maintenanceStateProvider가 false가 되면 자동으로 false로 초기화됨.
final maintenanceErrorProvider = StateProvider<bool>((ref) => false);
