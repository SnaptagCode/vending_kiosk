import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:vending_kiosk/core/data/datasources/remote/payment_api_client.dart';
import 'package:vending_kiosk/core/services/payment/disabled_payment_gateway.dart';
import 'package:vending_kiosk/core/services/payment/kscat_payment_gateway.dart';
import 'package:vending_kiosk/core/services/payment/payment_gateway.dart';
import 'package:vending_kiosk/core/services/payment/payment_mode_provider.dart';

part 'payment_gateway_provider.g.dart';

@Riverpod(keepAlive: true)
KscatPaymentGateway kscatPaymentGateway(Ref ref) {
  return KscatPaymentGateway(
    PaymentApiClient(),
    ref,
  );
}

@riverpod
PaymentGateway paymentGateway(Ref ref) {
  final kscat = ref.watch(kscatPaymentGatewayProvider);
  final isPaymentEnabled = ref.watch(paymentModeNotifierProvider);
  // 결제 OFF(무료 모드): approve/check 차단, cancel은 실제 단말로 위임
  return isPaymentEnabled ? kscat : DisabledPaymentGateway(kscat);
}
