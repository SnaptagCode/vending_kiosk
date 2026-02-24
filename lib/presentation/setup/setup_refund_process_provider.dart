import 'package:easy_localization/easy_localization.dart';
import 'package:vending_kiosk/core/common/constants/alert_key.dart';
import 'package:vending_kiosk/core/common/logger/slack_log_service.dart';
import 'package:vending_kiosk/core/data/models/entities/vending_print_item_entity.dart';
import 'package:vending_kiosk/core/data/models/enums/order_status.dart';
import 'package:vending_kiosk/core/data/models/request/update_order_request.dart';
import 'package:vending_kiosk/core/data/models/request/update_vending_order_status_request.dart';
import 'package:vending_kiosk/core/data/models/response/payment_response.dart';
import 'package:vending_kiosk/core/data/repositories/kiosk_repository.dart';
import 'package:vending_kiosk/core/data/repositories/payment_repository.dart';
import 'package:vending_kiosk/core/domain/entities/invoice.dart';
import 'package:vending_kiosk/presentation/kiosk_shell/kiosk_info_service.dart';
import 'package:vending_kiosk/presentation/setup/payment_history_provider.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'setup_refund_process_provider.g.dart';

@riverpod
class SetupRefundProcess extends _$SetupRefundProcess {
  @override
  FutureOr<PaymentResponse?> build() => null;

  Future<void> startRefund(VendingPrintItemEntity order) async {
    if (order.purchaseAuthNumber.isEmpty) {
      throw Exception('No payment auth number available');
    }
    if (order.completedAt == null) {
      throw Exception('No completed date available');
    }

    try {
      final Invoice invoice = Invoice.calculate(order.amount);
      state = const AsyncValue.loading();

      final response = await ref.read(paymentRepositoryProvider).cancel(
            totalAmount: invoice.total,
            originalApprovalNo: order.purchaseAuthNumber,
            originalApprovalDate: DateFormat('yyMMdd').format(DateTime.parse(order.completedAt!)),
          );
      SlackLogService().sendLogToSlack("refund response: $response");

      state = AsyncValue.data(response);
      await _updateOrderStatus(order);
      final currentPage = ref.read(ordersPageProvider()).requireValue.paging.currentPage;
      ref.read(ordersPageProvider().notifier).goToPage(currentPage);
    } catch (e) {
      state = AsyncValue.error(e, StackTrace.current);
      rethrow;
    }
  }

  Future<void> _updateOrderStatus(VendingPrintItemEntity order) async {
    final payment = state.value;
    final settings = ref.read(kioskInfoServiceProvider);

    if (settings == null) {
      throw Exception('No settings available');
    }
    final request = UpdateVendingOrderStatusRequest(
      kioskEventId: settings.kioskEventId,
      kioskMachineId: settings.kioskMachineId,
      status: payment?.orderState ?? OrderStatus.refunded_failed,
      amount: order.amount.toInt(),
      authSeqNumber: order.purchaseAuthNumber,
      detail: payment?.KSNET ?? '{}',
      approvalNumber: order.purchaseAuthNumber,
    );

    if (payment?.respCode == '7001') {
      await ref.read(kioskRepositoryProvider).updateVendingOrderStatus(
            order.kioskOrderId,
            request.copyWith(status: OrderStatus.refunded_failed, description: "기취소된 거래"),
          );
      SlackLogService().sendPaymentBroadcastLogToSlak(InfoKey.paymentRefundFail.key,
          paymentDescription:
              "동작로직: 관리자 환불\n- 사유: 기취소된 거래\n- 인증번호: ${order.purchaseAuthNumber}\n- 승인번호: ${order.purchaseAuthNumber}");
    } else {
      switch (payment?.res) {
        case '0000':
          await ref.read(kioskRepositoryProvider).updateVendingOrderStatus(
                order.kioskOrderId,
                request,
              );
        case '1000':
          await ref.read(kioskRepositoryProvider).updateVendingOrderStatus(
                order.kioskOrderId,
                request.copyWith(description: "고객취소"),
              );
          SlackLogService().sendPaymentBroadcastLogToSlak(InfoKey.paymentRefundFail.key,
              paymentDescription:
                  "동작로직: 관리자 환불\n- 사유: 사용자가 환불취소 누름\n- 인증번호: ${order.purchaseAuthNumber}\n- 승인번호: ${order.purchaseAuthNumber}");
          break;
        case '1004':
          await ref.read(kioskRepositoryProvider).updateVendingOrderStatus(
                order.kioskOrderId,
                request.copyWith(description: "시간초과"),
              );
          SlackLogService().sendPaymentBroadcastLogToSlak(InfoKey.paymentRefundFail.key,
              paymentDescription:
                  "동작로직: 관리자 환불\n- 사유: 시간초과\n- 인증번호: ${order.purchaseAuthNumber}\n- 승인번호: ${order.purchaseAuthNumber}");
          break;
        default:
          await ref.read(kioskRepositoryProvider).updateVendingOrderStatus(
                order.kioskOrderId,
                request.copyWith(description: "확인필요"),
              );
          SlackLogService().sendPaymentBroadcastLogToSlak(InfoKey.paymentRefundFail.key,
              paymentDescription:
                  "동작로직: 관리자 환불\n- 사유: 확인필요\n- 인증번호: ${order.purchaseAuthNumber}\n- 승인번호: ${order.purchaseAuthNumber}");
      }
    }
  }
}
