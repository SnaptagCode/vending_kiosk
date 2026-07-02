import 'package:vending_kiosk/core/data/models/response/payment_response.dart';
import 'package:vending_kiosk/core/services/payment/payment_gateway_provider.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'payment_provider.g.dart';

@riverpod
class PaymentNotifier extends _$PaymentNotifier {
  @override
  FutureOr<PaymentResponse?> build() {
    return null;
  }

  Future<void> processPayment(int totalAmount) async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() async {
      final repository = ref.read(paymentGatewayProvider);
      return await repository.approve(totalAmount: totalAmount);
    });
  }

  void reset() {
    state = const AsyncValue.data(null);
  }
}
