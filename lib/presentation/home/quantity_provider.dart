import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'quantity_provider.g.dart';

@riverpod
class Quantity extends _$Quantity {
  @override
  int build() => 1;

  void setQuantity(int value) {
    if (value >= 1) {
      state = value;
    }
  }

  void increment() {
    state = state + 1;
  }

  void decrement() {
    if (state > 1) {
      state = state - 1;
    }
  }

  void reset() {
    state = 1;
  }
}
