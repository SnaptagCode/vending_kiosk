import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:vending_kiosk/presentation/print/print_service.dart';

part 'print_process_screen_provider.g.dart';

@riverpod
class PrintProcessScreenProvider extends _$PrintProcessScreenProvider {
  @override
  FutureOr<void> build() async {
    try {
      await ref.read(printServiceProvider.notifier).printCard();
    } catch (e) {
      rethrow;
    }
  }
}
