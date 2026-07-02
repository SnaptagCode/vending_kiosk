import 'package:vending_kiosk/core/data/models/response/kscat_device_response.dart';
import 'package:vending_kiosk/core/data/models/response/payment_response.dart';
import 'package:vending_kiosk/core/services/payment/kscat_payment_gateway.dart';
import 'package:vending_kiosk/core/services/payment/payment_gateway.dart';

/// 결제 OFF(무료 모드) 상태의 게이트웨이.
/// approve/check는 차단하되, OFF 이전 유료 주문의 환불(cancel)은
/// 실제 단말로 위임해 항상 동작해야 한다.
class DisabledPaymentGateway implements PaymentGateway {
  DisabledPaymentGateway(this._delegate);

  final KscatPaymentGateway _delegate;

  @override
  Future<PaymentResponse> approve({
    required int totalAmount,
  }) async {
    throw const PaymentDisabledException();
  }

  @override
  Future<KscatDeviceResponse> check() async {
    throw const PaymentDisabledException();
  }

  @override
  Future<PaymentResponse> cancel({
    required int totalAmount,
    required String originalApprovalNo,
    required String originalApprovalDate,
  }) {
    return _delegate.cancel(
      totalAmount: totalAmount,
      originalApprovalNo: originalApprovalNo,
      originalApprovalDate: originalApprovalDate,
    );
  }
}
