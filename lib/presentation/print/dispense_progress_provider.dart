import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 서버가 알려준 카드 재고 스냅샷.
/// [current]는 재고 미관리 머신이거나 아직 응답을 받지 못했으면 null — 0(카드 소진)과 구분해야 한다.
class DispenseProgress {
  final int? current;
  final int total;

  const DispenseProgress({
    required this.current,
    required this.total,
  });

  DispenseProgress copyWith({
    int? current,
    int? total,
  }) {
    return DispenseProgress(
      current: current ?? this.current,
      total: total ?? this.total,
    );
  }

  double get percentage {
    final current = this.current;
    return (current != null && total > 0) ? current / total : 0.0;
  }

  bool get isCompleted {
    final current = this.current;
    return current != null && total > 0 && current >= total;
  }
}

class DispenseProgressNotifier extends StateNotifier<DispenseProgress> {
  DispenseProgressNotifier() : super(const DispenseProgress(current: null, total: 0));

  void updateCurrent(int current, int total) {
    state = state.copyWith(current: current, total: total);
  }

  void reset() {
    state = const DispenseProgress(current: null, total: 0);
  }

  void setProgress(int current, int total) {
    state = DispenseProgress(current: current, total: total);
  }
}

final dispenseProgressNotifierProvider = StateNotifierProvider<DispenseProgressNotifier, DispenseProgress>(
  (ref) => DispenseProgressNotifier(),
);
