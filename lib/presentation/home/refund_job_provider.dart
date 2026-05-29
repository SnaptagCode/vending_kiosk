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
    final keepAlive = ref.keepAlive();
    state = const AsyncValue.loading();
    try {
      final result = await _processRefund(response);
      state = AsyncValue.data(result);
    } catch (e) {
      // _processRefund에서 예상치 못한 예외 — job이 pick 상태로 남지 않도록 안전망 종결
      final printJobId = response.printJobId;
      SlackLogService().sendErrorLogToSlack('환불 job($printJobId) 예상치 못한 오류: $e');
      if (printJobId != null) {
        try {
          await ref.read(kioskRepositoryProvider).failVendingPrintJob(
                printJobId: printJobId,
                failureReason: '환불 처리 중 예상치 못한 오류: $e',
              );
        } catch (e2) {
          SlackLogService().sendErrorLogToSlack('환불 job($printJobId) failVendingPrintJob 실패: $e2');
        }
      }
      state = AsyncValue.data(RefundFailure(e is PaymentFailedException ? e.message : '환불을 완료하지 못했어요.'));
    } finally {
      keepAlive.close();
    }
  }

  Future<RefundResult?> _processRefund(VendingPrintPollingResponse response) async {
    final refundInfo = response.refundInfo;
    final printJobId = response.printJobId;
    final kioskOrderId = response.kioskOrderId;

    // cancel() 호출 전에 필수 필드를 모두 검증 — 이후 강제 언래핑 없음
    if (refundInfo == null || printJobId == null || kioskOrderId == null) {
      final reason = '환불 job 필수 필드 누락 '
          '(printJobId=$printJobId, kioskOrderId=$kioskOrderId, refundInfo=${refundInfo == null ? 'null' : 'ok'})';
      SlackLogService().sendErrorLogToSlack(reason);
      if (printJobId != null) {
        try {
          await ref.read(kioskRepositoryProvider).failVendingPrintJob(
                printJobId: printJobId,
                failureReason: reason,
              );
        } catch (e) {
          SlackLogService().sendErrorLogToSlack('환불 job($printJobId) failVendingPrintJob 실패: $e');
        }
      }
      return null;
    }

    // Phase 1: 결제사 취소 요청
    // 이 단계가 throw되면 실제 환불이 미완료이므로 failVendingPrintJob 가능
    final PaymentResponse paymentResponse;
    try {
      paymentResponse = await ref.read(paymentRepositoryProvider).cancel(
            totalAmount: refundInfo.amount,
            originalApprovalNo: refundInfo.originalApprovalNo,
            originalApprovalDate: refundInfo.originalApprovalDate,
          );
    } catch (e) {
      try {
        await ref.read(kioskRepositoryProvider).failVendingPrintJob(
              printJobId: printJobId,
              failureReason: '환불 실패: $e',
            );
      } catch (e2) {
        SlackLogService().sendErrorLogToSlack('환불 job($printJobId) failVendingPrintJob 실패: $e2');
      }
      return RefundFailure(e is PaymentFailedException ? e.message : '환불을 완료하지 못했어요.');
    }

    // Phase 2: cancel 결과에 따른 후속 처리
    // isSuccess=true이면 실제 환불이 완료된 상태 — 이후 failVendingPrintJob 금지
    final isSuccess = paymentResponse.isSuccess || paymentResponse.isAlreadyCanceled;
    final kioskInfo = ref.read(kioskInfoServiceProvider);

    if (kioskInfo == null) {
      SlackLogService().sendErrorLogToSlack(
        '환불 job($printJobId) kioskInfo null — 수동 정산 필요 (isSuccess=$isSuccess)',
      );
      try {
        if (isSuccess) {
          await ref.read(kioskRepositoryProvider).succeedVendingPrintJob(printJobId);
        } else {
          await ref.read(kioskRepositoryProvider).failVendingPrintJob(
                printJobId: printJobId,
                failureReason: 'kioskInfo null',
              );
        }
      } catch (e) {
        SlackLogService().sendErrorLogToSlack('환불 job($printJobId) job 종결 실패: $e');
      }
      return null;
    }

    final int machineId;
    final UpdateVendingOrderStatusRequest statusRequest;
    try {
      machineId = kioskInfo.kioskMachineId;
      statusRequest = UpdateVendingOrderStatusRequest(
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
      );
    } catch (e) {
      // cancel 결과는 이미 확정된 상태 — failVendingPrintJob 금지
      SlackLogService().sendErrorLogToSlack(
        '환불 job($printJobId) 상태 요청 구성 실패 — 수동 정산 필요: $e',
      );
      try {
        if (isSuccess) {
          await ref.read(kioskRepositoryProvider).succeedVendingPrintJob(printJobId);
        } else {
          await ref.read(kioskRepositoryProvider).failVendingPrintJob(
                printJobId: printJobId,
                failureReason: '상태 요청 구성 실패: $e',
              );
        }
      } catch (e2) {
        SlackLogService().sendErrorLogToSlack('환불 job($printJobId) job 종결 실패: $e2');
      }
      return isSuccess ? RefundSuccess(refundInfo.amount) : null;
    }

    // updateVendingOrderStatus 3회 재시도 (기존 payment_service.dart 패턴 동일)
    for (int attempt = 1; attempt <= 3; attempt++) {
      try {
        await ref.read(kioskRepositoryProvider).updateVendingOrderStatus(kioskOrderId, statusRequest);
        break;
      } catch (e) {
        if (attempt >= 3) {
          SlackLogService().sendErrorLogToSlack(
            '[MachineId: $machineId] 환불 job($printJobId) updateVendingOrderStatus 3회 실패 — 수동 정산 필요: $e',
          );
        }
      }
    }

    if (isSuccess) {
      // cancel 성공 — updateVendingOrderStatus 실패해도 failVendingPrintJob 금지
      try {
        await ref.read(kioskRepositoryProvider).succeedVendingPrintJob(printJobId);
      } catch (e) {
        SlackLogService().sendErrorLogToSlack('환불 job($printJobId) succeedVendingPrintJob 실패: $e');
      }
      SlackLogService().sendLogToSlack(
          '[MachineId: $machineId] polling 환불 성공 | job=$printJobId | ${refundInfo.amount}원');
      return RefundSuccess(refundInfo.amount);
    } else {
      final failReason =
          (paymentResponse.msg?.isNotEmpty == true ? paymentResponse.msg : paymentResponse.message1) ?? '환불 실패';
      try {
        await ref.read(kioskRepositoryProvider).failVendingPrintJob(
              printJobId: printJobId,
              failureReason: failReason,
            );
      } catch (e) {
        SlackLogService().sendErrorLogToSlack('환불 job($printJobId) failVendingPrintJob 실패: $e');
      }
      SlackLogService().sendErrorLogToSlack(
        '[MachineId: $machineId] polling 환불 실패 | job=$printJobId | $failReason',
      );
      return RefundFailure('환불을 완료하지 못했어요.');
    }
  }
}
