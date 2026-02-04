import 'package:flutter_snaptag_kiosk/core/common/logger/logger_service.dart';
import 'package:flutter_snaptag_kiosk/core/data/repositories/kiosk_repository.dart';
import 'package:flutter_snaptag_kiosk/core/domain/response/back_photo_card_response.dart';
import 'package:flutter_snaptag_kiosk/lib.dart';
import 'package:flutter_snaptag_kiosk/presentation/kiosk_shell/kiosk_info_service.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'verify_photo_card_provider.g.dart';

@Riverpod(keepAlive: true)
class VerifyPhotoCard extends _$VerifyPhotoCard {
  @override
  AsyncValue<BackPhotoCardResponse?> build() {
    return const AsyncValue.data(null);
  }

  Future<void> verify(String code) async {
    state = const AsyncValue.loading();

    state = await AsyncValue.guard(() async {
      final kioskEventId = ref.read(kioskInfoServiceProvider)?.kioskEventId;

      if (kioskEventId == null) {
        throw Exception('No kiosk event id available');
      }
      final response = await ref.read(kioskRepositoryProvider).getBackPhotoCard(
            kioskEventId,
            code,
          );
      logger.i('BackPhotoCardResponse: ${response.toJson()}');
      return response;
    });
  }

  void reset() {
    state = const AsyncValue.data(null);
  }

  /// 상태를 직접 업데이트하는 함수
  void updateState(BackPhotoCardResponse? response) {
    state = AsyncValue.data(response);
  }
}
