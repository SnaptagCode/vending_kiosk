import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:vending_kiosk/core/common/logger/slack_log_service.dart';
import 'package:vending_kiosk/core/data/models/response/payment_response.dart';
import 'package:vending_kiosk/presentation/home/payment/create_order_info_state.dart';

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
          SlackLogService().sendLogToSlack('No order response available: Null ApprovalNo');
          // throw Exception('No order response available');
        }
        SlackLogService().sendLogToSlack('OrderResponse : $orderResponse \n PaymentResponse: $response');
      }

      SlackLogService().sendLogToSlack('PaymentResponse: $response');
    } catch (e) {
      SlackLogService().sendLogToSlack('PaymentResponseState Exception: $e');
    }

    state = response;
  }

  void reset() => state = null;
}
