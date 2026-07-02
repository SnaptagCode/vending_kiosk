import 'package:vending_kiosk/core/data/models/response/kscat_device_response.dart';
import 'package:vending_kiosk/core/data/models/response/payment_response.dart';

/// 결제 단말 연동 추상화.
/// 구현체 선택은 paymentGatewayProvider가 담당한다.
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

/// 결제 비활성(무료 모드) 상태에서 approve/check 호출 시 발생.
class PaymentDisabledException implements Exception {
  const PaymentDisabledException([this.message = '결제 기능이 비활성화되어 있습니다.']);

  final String message;

  @override
  String toString() => message;
}
