import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:vending_kiosk/core/common/logger/slack_log_service.dart';
import 'package:vending_kiosk/core/data/models/enums/order_status.dart';
import 'package:vending_kiosk/core/data/models/request/update_vending_order_status_request.dart';
import 'package:vending_kiosk/core/data/models/response/payment_response.dart';
import 'package:vending_kiosk/core/data/models/response/vending_print_polling_response.dart';
import 'package:vending_kiosk/core/data/repositories/kiosk_repository.dart';
import 'package:vending_kiosk/core/data/repositories/payment_repository.dart';
import 'package:vending_kiosk/presentation/home/payment/payment_failed_type.dart';
import 'package:vending_kiosk/presentation/kiosk_shell/kiosk_info_service.dart';

part 'refund_job_provider.g.dart';

sealed class RefundResult {
  const RefundResult();
}

final class RefundSuccess extends RefundResult {
  final int amount;
  const RefundSuccess(this.amount);
}

final class RefundFailure extends RefundResult {
  final String reason;
  const RefundFailure(this.reason);
}

@riverpod
class RefundJobNotifier extends _$RefundJobNotifier {
  @override
  AsyncValue<RefundResult?> build() => const AsyncValue.data(null);

  Future<void> process(VendingPrintPollingResponse response) async {
    if (state.isLoading) return;
    state = const AsyncValue.loading();
    try {
      final result = await _processRefund(response);
      state = AsyncValue.data(result);
    } catch (e) {
      state = AsyncValue.data(RefundFailure(e is PaymentFailedException ? e.message : '환불을 완료하지 못했어요.'));
    }
  }

  Future<RefundResult?> _processRefund(VendingPrintPollingResponse response) async {
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
      return null;
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
        return null;
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
        return RefundSuccess(refundInfo.amount);
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
        return RefundFailure('환불을 완료하지 못했어요.');
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
      return RefundFailure(e is PaymentFailedException ? e.message : '환불을 완료하지 못했어요.');
    }
  }
}
