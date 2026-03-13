import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vending_kiosk/core/common/logger/logger_service.dart';
import 'package:vending_kiosk/core/data/models/response/vending_print_list_response.dart';
import 'package:vending_kiosk/core/data/repositories/kiosk_repository.dart';
import 'package:vending_kiosk/presentation/kiosk_shell/kiosk_info_service.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'payment_history_provider.g.dart';

/// 재출력 후 돌아올 때 이전 페이지를 복원하기 위한 저장소
final savedHistoryPageProvider = StateProvider<int>((ref) => 1);

@riverpod
class OrdersPage extends _$OrdersPage {
  final int _pageSize = 15;
  int get kioskEventId => ref.read(kioskInfoServiceProvider)?.kioskEventId ?? 0;
  int get kioskMachineId => ref.read(kioskInfoServiceProvider)?.kioskMachineId ?? 0;

  @override
  Future<VendingPrintListResponse> build({int page = 1}) async {
    final VendingPrintListResponse response = await ref.read(kioskRepositoryProvider).getVendingPrintList(
          kioskEventId: kioskEventId,
          kioskMachineId: kioskMachineId,
          pageSize: _pageSize,
          currentPage: page,
        );
    logger.i('response: $response');
    return response;
  }

  Future<void> goToPage(int newPage) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() => ref.read(kioskRepositoryProvider).getVendingPrintList(
          kioskEventId: kioskEventId,
          kioskMachineId: kioskMachineId,
          pageSize: _pageSize,
          currentPage: newPage,
        ));
  }
}
