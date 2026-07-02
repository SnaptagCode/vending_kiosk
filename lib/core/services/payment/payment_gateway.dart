import 'package:vending_kiosk/core/data/models/response/kscat_device_response.dart';
import 'package:vending_kiosk/core/data/models/response/payment_response.dart';

abstract class PaymentGateway {
  Future<PaymentResponse> approve({
    required int totalAmount,
  });

  Future<KscatDeviceResponse> check();

  Future<PaymentResponse> cancel({
    required int totalAmount,
    required String originalApprovalNo,
    required String originalApprovalDate,
  });
}

class PaymentDisabledException implements Exception {
  const PaymentDisabledException([this.message = '결제 기능이 비활성화되어 있습니다.']);

  final String message;

  @override
  String toString() => message;
}
