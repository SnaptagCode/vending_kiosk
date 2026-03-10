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
  PrintQuantityNotifier() : super(const PrintQuantity(current: 0, total: 1));

  void setQuantity(int value) {
    state = state.copyWith(current: 0, total: value > 0 ? value : 1);
  }

  void increment() {
    state = state.copyWith(current: state.current + 1);
  }

  void decrement() {
    state = state.copyWith(current: state.current - 1);
  }

  void reset() {
    state = state.copyWith(current: 0, total: 1);
  }
}

final printQuantityNotifierProvider = StateNotifierProvider<PrintQuantityNotifier, PrintQuantity>(
  (ref) => PrintQuantityNotifier(),
);

/// 재출력 모드 여부 — true이면 출력 완료 후 출력 내역 화면으로 이동
final reprintModeProvider = StateProvider<bool>((ref) => false);

/// 재출력 대상 IDs — null이면 일반 출력(createOrderInfoProvider 사용)
final reprintIdsProvider = StateProvider<List<int>?>((ref) => null);
