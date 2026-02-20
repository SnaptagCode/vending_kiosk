import 'package:flutter_riverpod/flutter_riverpod.dart';

/// State for tracking card dispensing progress
class DispenseProgress {
  final int current;
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

  double get percentage => total > 0 ? current / total : 0.0;
  bool get isCompleted => current >= total && total > 0;
}

class DispenseProgressNotifier extends StateNotifier<DispenseProgress> {
  DispenseProgressNotifier() : super(const DispenseProgress(current: 0, total: 0));

  void initialize(int total) {
    state = DispenseProgress(current: 0, total: total);
  }

  void increment() {
    if (state.current < state.total) {
      state = state.copyWith(current: state.current + 1);
    }
  }

  void decrement() {
    if (state.current > 0) {
      state = state.copyWith(current: state.current - 1);
    }
  }

  void updateCurrent(int current, int total) {
    state = state.copyWith(current: current, total: total);
  }

  void reset() {
    state = const DispenseProgress(current: 0, total: 0);
  }

  void setProgress(int current, int total) {
    state = DispenseProgress(current: current, total: total);
  }
}

final dispenseProgressNotifierProvider = StateNotifierProvider<DispenseProgressNotifier, DispenseProgress>(
  (ref) => DispenseProgressNotifier(),
);
