import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:vending_kiosk/core/common/logger/slack_log_service.dart';
import 'package:vending_kiosk/core/data/models/enums/order_status.dart';
import 'package:vending_kiosk/core/data/models/request/update_vending_order_status_request.dart';
import 'package:vending_kiosk/core/data/models/response/payment_response.dart';
import 'package:vending_kiosk/core/data/models/response/vending_print_polling_response.dart';
import 'package:vending_kiosk/core/data/repositories/kiosk_repository.dart';
import 'package:vending_kiosk/core/data/repositories/payment_repository.dart';
import 'package:vending_kiosk/presentation/kiosk_shell/kiosk_info_service.dart';

part 'refund_job_provider.g.dart';

@riverpod
class RefundJobNotifier extends _$RefundJobNotifier {
  @override
  AsyncValue<void> build() => const AsyncValue.data(null);

  Future<void> process(VendingPrintPollingResponse response) async {
    if (state.isLoading) return;
    state = const AsyncValue.loading();
    try {
      await _processRefund(response);
    } finally {
      state = const AsyncValue.data(null);
    }
  }

  Future<void> _processRefund(VendingPrintPollingResponse response) async {
    final refundInfo = response.refundInfo;

    if (refundInfo == null) {
      final reason = '환불 job(${response.printJobId}) refundInfo 누락';
      SlackLogService().sendErrorLogToSlack(reason);
      if (response.printJobId != null) {
        try {
          await ref.read(kioskRepositoryProvider).failVendingPrintJob(
                printJobId: response.printJobId!,
                failureReason: reason,
              );
        } catch (e) {
          SlackLogService().sendErrorLogToSlack('환불 job(${response.printJobId}) failVendingPrintJob 실패: $e');
        }
      }
      return;
    }

    try {
      final paymentResponse = await ref.read(paymentRepositoryProvider).cancel(
            totalAmount: refundInfo.amount,
            originalApprovalNo: refundInfo.originalApprovalNo,
            originalApprovalDate: refundInfo.originalApprovalDate,
          );

      final isSuccess = paymentResponse.isSuccess;
      final kioskInfo = ref.read(kioskInfoServiceProvider);
      if (kioskInfo == null) {
        SlackLogService().sendErrorLogToSlack('환불 job(${response.printJobId}) kioskInfo null — 수동 정산 필요');
        await ref.read(kioskRepositoryProvider).succeedVendingPrintJob(response.printJobId!);
        return;
      }
      final machineId = kioskInfo.kioskMachineId;

      await ref.read(kioskRepositoryProvider).updateVendingOrderStatus(
            response.kioskOrderId!,
            UpdateVendingOrderStatusRequest(
              kioskEventId: refundInfo.kioskEventId,
              kioskMachineId: kioskInfo.kioskMachineId,
              status: isSuccess ? OrderStatus.refunded : OrderStatus.refunded_failed,
              amount: refundInfo.amount,
              authSeqNumber: isSuccess ? (paymentResponse.approvalNo ?? '-') : '-',
              approvalNumber: isSuccess ? (paymentResponse.approvalNo ?? '-') : '-',
              description: isSuccess
                  ? null
                  : (paymentResponse.msg?.isNotEmpty == true ? paymentResponse.msg : paymentResponse.message1),
              detail: paymentResponse.KSNET,
            ),
          );

      if (isSuccess) {
        await ref.read(kioskRepositoryProvider).succeedVendingPrintJob(response.printJobId!);
        SlackLogService().sendLogToSlack(
            '[MachineId: $machineId] polling 환불 성공 | job=${response.printJobId} | ${refundInfo.amount}원');
      } else {
        final failReason =
            (paymentResponse.msg?.isNotEmpty == true ? paymentResponse.msg : paymentResponse.message1) ?? '환불 실패';
        await ref.read(kioskRepositoryProvider).failVendingPrintJob(
              printJobId: response.printJobId!,
              failureReason: failReason,
            );
        SlackLogService().sendErrorLogToSlack(
          '[MachineId: $machineId] polling 환불 실패 | job=${response.printJobId} | $failReason',
        );
      }
    } catch (e) {
      if (response.printJobId != null) {
        try {
          await ref.read(kioskRepositoryProvider).failVendingPrintJob(
                printJobId: response.printJobId!,
                failureReason: '환불 실패: $e',
              );
        } catch (e2) {
          SlackLogService().sendErrorLogToSlack('환불 job(${response.printJobId}) failVendingPrintJob 실패: $e2');
        }
      }
    }
  }
}
