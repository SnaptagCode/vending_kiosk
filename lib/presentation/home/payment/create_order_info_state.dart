import 'package:vending_kiosk/core/data/models/response/create_vending_order_response.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'create_order_info_state.g.dart';

@Riverpod(keepAlive: true)
class CreateOrderInfo extends _$CreateOrderInfo {
  @override
  CreateVendingOrderResponse? build() => null;

  void update(CreateVendingOrderResponse response) {
    state = response;
  }

  void reset() {
    state = null;
  }
}
