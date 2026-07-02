import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:vending_kiosk/core/data/datasources/remote/payment_api_client.dart';
import 'package:vending_kiosk/core/services/payment/kscat_payment_gateway.dart';
import 'package:vending_kiosk/core/services/payment/payment_gateway.dart';

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
  // P0: 항상 KSCAT. P1에서 paymentModeProvider 기준으로 Disabled 구현체 스왑 예정.
  return ref.watch(kscatPaymentGatewayProvider);
}
