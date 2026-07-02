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
  return ref.watch(kscatPaymentGatewayProvider);
}
