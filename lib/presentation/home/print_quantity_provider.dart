import 'package:flutter_riverpod/flutter_riverpod.dart';

class PrintQuantity {
  final int current;
  final int total;

  const PrintQuantity({
    required this.current,
    required this.total,
  });

  PrintQuantity copyWith({
    int? current,
    int? total,
  }) {
    return PrintQuantity(
      current: current ?? this.current,
      total: total ?? this.total,
    );
  }

  double get percentage => total > 0 ? current / total : 0.0;
  bool get isCompleted => current == total && total > 0;
}

class PrintQuantityNotifier extends StateNotifier<PrintQuantity> {
  PrintQuantityNotifier() : super(const PrintQuantity(current: 0, total: 0));

  void setQuantity(int value) {
    state = state.copyWith(total: value);
  }

  void increment() {
    state = state.copyWith(current: state.current + 1);
  }

  void decrement() {
    state = state.copyWith(current: state.current - 1);
  }

  void reset() {
    state = state.copyWith(current: 0, total: 0);
  }
}

final printQuantityNotifierProvider = StateNotifierProvider<PrintQuantityNotifier, PrintQuantity>(
  (ref) => PrintQuantityNotifier(),
);
