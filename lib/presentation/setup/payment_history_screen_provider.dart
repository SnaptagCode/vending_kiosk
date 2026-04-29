import 'package:easy_localization/easy_localization.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:vending_kiosk/core/common/constants/alert_key.dart';
import 'package:vending_kiosk/core/common/logger/logger_service.dart';
import 'package:vending_kiosk/core/common/logger/slack_log_service.dart';
import 'package:vending_kiosk/core/data/models/entities/vending_print_item_entity.dart';
import 'package:vending_kiosk/core/data/models/enums/order_status.dart';
import 'package:vending_kiosk/core/data/models/request/update_vending_order_status_request.dart';
import 'package:vending_kiosk/core/data/models/response/payment_response.dart';
import 'package:vending_kiosk/core/data/repositories/kiosk_repository.dart';
import 'package:vending_kiosk/core/data/repositories/payment_repository.dart';
import 'package:vending_kiosk/core/domain/entities/invoice.dart';
import 'package:vending_kiosk/presentation/home/print_quantity_provider.dart';
import 'package:vending_kiosk/presentation/kiosk_shell/kiosk_info_service.dart';
import 'package:vending_kiosk/presentation/setup/payment_history_provider.dart';

part 'payment_history_screen_provider.g.dart';

class PaymentHistoryState {
  final AsyncValue<PaymentResponse?> refundState;

  const PaymentHistoryState({
    this.refundState = const AsyncValue.data(null),
  });

  PaymentHistoryState copyWith({
    AsyncValue<PaymentResponse?>? refundState,
  }) {
    return PaymentHistoryState(
      refundState: refundState ?? this.refundState,
    );
  }
}

@riverpod
class PaymentHistoryNotifier extends _$PaymentHistoryNotifier {
  @override
  PaymentHistoryState build() => const PaymentHistoryState();

  /// 화면 진입 시 이전 페이지 복원
  void restoreSavedPage() {
    final savedPage = ref.read(savedHistoryPageProvider);
    if (savedPage > 1) {
      ref.read(ordersPageProvider().notifier).goToPage(savedPage);
    }
  }

  /// 페이지 이동 + 저장
  void goToPage(int page) {
    ref.read(savedHistoryPageProvider.notifier).state = page;
    ref.read(ordersPageProvider().notifier).goToPage(page);
  }

  // ─────────────────────────────────────────────
  // 재출력
  // ─────────────────────────────────────────────

  /// 재출력 전 재고 확인
  ///
  /// - true: 재고 충분
  /// - false: 재고 부족 → 화면에서 다이얼로그 처리 후 [proceedReprint] 호출 여부 결정
  Future<bool> checkStock(VendingPrintItemEntity order) async {
    try {
      final kioskInfo = ref.read(kioskInfoServiceProvider);
      if (kioskInfo == null) throw Exception('Kiosk info is null');

      final remainingQuantity = order.totalCount - order.completedCount;
      final stockResponse = await ref.read(kioskRepositoryProvider).getMachineCardStock(kioskInfo.kioskMachineId);

      logger.i('checkStock: remaining=$remainingQuantity, stock=${stockResponse.cardCurrentCount}');
      return remainingQuantity <= stockResponse.cardCurrentCount;
    } catch (e) {
      logger.e('PaymentHistoryNotifier.checkStock failed', error: e);
      rethrow;
    }
  }

  /// 재출력 API 호출 및 상태 설정
  ///
  /// - true: 출력 화면으로 이동 가능
  /// - false: reprintableIds 없음 (이동 불필요)
  Future<bool> proceedReprint(VendingPrintItemEntity order) async {
    try {
      final response = await ref.read(kioskRepositoryProvider).reprintVendingOrder(order.kioskOrderId);

      if (response.reprintableIds.isEmpty) return false;

      ref.read(reprintIdsProvider.notifier).state = response.reprintableIds;
      ref.read(printQuantityNotifierProvider.notifier).setQuantity(response.reprintableIds.length);
      return true;
    } catch (e) {
      logger.e('PaymentHistoryNotifier.proceedReprint failed', error: e);
      rethrow;
    }
  }

  // ─────────────────────────────────────────────
  // 환불
  // ─────────────────────────────────────────────

  Future<void> startRefund(VendingPrintItemEntity order) async {
    if (order.purchaseAuthNumber.isEmpty) {
      state = state.copyWith(
        refundState: AsyncValue.error(Exception('No payment auth number available'), StackTrace.current),
      );
      throw Exception('No payment auth number available');
    }
    if (order.completedAt == null) {
      state = state.copyWith(
        refundState: AsyncValue.error(Exception('No completed date available'), StackTrace.current),
      );
      throw Exception('No completed date available');
    }

    try {
      final Invoice invoice = Invoice.calculate(order.amount);
      state = state.copyWith(refundState: const AsyncValue.loading());

      final response = await ref.read(paymentRepositoryProvider).cancel(
            totalAmount: invoice.total,
            originalApprovalNo: order.purchaseAuthNumber,
            originalApprovalDate: DateFormat('yyMMdd').format(DateTime.parse(order.completedAt!)),
          );
      final machineId = ref.read(kioskInfoServiceProvider)?.kioskMachineId.toString() ?? 'unknown';
      SlackLogService().sendLogToSlack('*[MachineId: $machineId]*\nrefund response: $response');

      state = state.copyWith(refundState: AsyncValue.data(response));
      await _updateOrderStatus(order, response);

      // 환불 후 현재 페이지 갱신
      final currentPage = ref.read(ordersPageProvider()).value?.paging.currentPage ?? 1;
      ref.read(ordersPageProvider().notifier).goToPage(currentPage);
    } catch (e) {
      state = state.copyWith(refundState: AsyncValue.error(e, StackTrace.current));
      rethrow;
    }
  }

  Future<void> _updateOrderStatus(VendingPrintItemEntity order, PaymentResponse payment) async {
    final settings = ref.read(kioskInfoServiceProvider);
    if (settings == null) throw Exception('No settings available');

    final request = UpdateVendingOrderStatusRequest(
      kioskEventId: settings.kioskEventId,
      kioskMachineId: settings.kioskMachineId,
      status: payment.orderState,
      amount: order.amount.toInt(),
      authSeqNumber: order.purchaseAuthNumber,
      detail: payment.KSNET,
      approvalNumber: order.purchaseAuthNumber,
    );

    final (status, description, slackReason) = _resolveRefundOutcome(payment);

    await ref.read(kioskRepositoryProvider).updateVendingOrderStatus(
          order.kioskOrderId,
          request.copyWith(status: status, description: description),
        );

    if (slackReason != null) {
      SlackLogService().sendPaymentBroadcastLogToSlak(
        InfoKey.paymentRefundFail.key,
        paymentDescription:
            '동작로직: 관리자 환불\n- 사유: $slackReason\n- 인증번호: ${order.purchaseAuthNumber}\n- 승인번호: ${order.purchaseAuthNumber}',
      );
    }
  }

  /// respCode / res 조합으로 (주문상태, 설명, 슬랙사유) 결정
  /// slackReason == null → 슬랙 미전송 (정상 환불)
  (OrderStatus, String?, String?) _resolveRefundOutcome(PaymentResponse payment) {
    if (payment.respCode != '0000') {
      return switch (payment.respCode) {
        '7001' => (OrderStatus.refunded_failed, '기취소된 거래', '기취소된 거래'),
        '7003' => (OrderStatus.refunded_failed, '단말번호 상이', '환불 실패'),
        _ => (OrderStatus.refunded_failed, '확인필요', '확인필요'),
      };
    }

    return switch (payment.res) {
      '0000' => (OrderStatus.refunded, null, null),
      '1000' => (OrderStatus.refunded_failed, '고객취소', '사용자가 환불취소 누름'),
      '1004' => (OrderStatus.refunded_failed, '시간초과', '시간초과'),
      _ => (OrderStatus.refunded_failed, '확인필요', '확인필요'),
    };
  }
}
