import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:vending_kiosk/core/common/logger/slack_log_service.dart';
import 'package:vending_kiosk/core/data/models/response/payment_response.dart';
import 'package:vending_kiosk/presentation/home/payment/create_order_info_state.dart';
import 'package:vending_kiosk/presentation/kiosk_shell/kiosk_info_service.dart';

part 'payment_response_state.g.dart';

@Riverpod(keepAlive: true)
class PaymentResponseState extends _$PaymentResponseState {
  @override
  PaymentResponse? build() => null;

  void update(PaymentResponse response) {
    try {
      final approvalNo = response.approvalNo ?? '';
      if (response.res != '0000' || approvalNo.trim().isEmpty) {
        final machineId = ref.read(kioskInfoServiceProvider)?.kioskMachineId.toString() ?? 'unknown';
        final orderResponse = ref.read(createOrderInfoProvider);
        if (orderResponse == null) {
          SlackLogService().sendLogToSlack('*[MachineId: $machineId]*\nNo order response available: Null ApprovalNo');
          // throw Exception('No order response available');
        }
        SlackLogService()
            .sendLogToSlack('*[MachineId: $machineId]*\nOrderResponse : $orderResponse \n PaymentResponse: $response');
      }

      // SlackLogService().sendLogToSlack('PaymentResponse: $response');
    } catch (e) {
      SlackLogService().sendLogToSlack('PaymentResponseState Exception: $e');
    }

    state = response;
  }

  void reset() => state = null;
}
