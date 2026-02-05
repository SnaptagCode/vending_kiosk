import 'package:vending_kiosk/core/common/logger/slack_log_service.dart';
import 'package:vending_kiosk/core/data/models/response/payment_response.dart';
import 'package:vending_kiosk/lib.dart';
import 'package:vending_kiosk/presentation/home/create_order_info_state.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'payment_response_state.g.dart';

@Riverpod(keepAlive: true)
class PaymentResponseState extends _$PaymentResponseState {
  @override
  PaymentResponse? build() => null;

  void update(PaymentResponse response) {
    try {
      final approvalNo = response.approvalNo ?? '';
      if (response.res != '0000' || approvalNo.trim().isEmpty) {
        final orderResponse = ref.read(createOrderInfoProvider);
        if (orderResponse == null) {
          SlackLogService().sendWarningLogToSlack('No order response available: Null ApprovalNo');
          // throw Exception('No order response available');
        }
        SlackLogService().sendWarningLogToSlack('OrderResponse : $orderResponse \n PaymentResponse: $response');
      }

      SlackLogService().sendLogToSlack('PaymentResponse: $response');
    } catch (e) {
      SlackLogService().sendLogToSlack('PaymentResponseState Exception: $e');
    }

    state = response;
  }

  void reset() => state = null;
}
