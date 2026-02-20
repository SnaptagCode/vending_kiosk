import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'print_quantity_provider.g.dart';

@riverpod
class PrintQuantity extends _$PrintQuantity {
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
