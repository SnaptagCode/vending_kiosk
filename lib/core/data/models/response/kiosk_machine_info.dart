import 'package:freezed_annotation/freezed_annotation.dart';

part 'kiosk_machine_info.freezed.dart';
part 'kiosk_machine_info.g.dart';

@freezed
abstract class KioskMachineInfo with _$KioskMachineInfo {
  const factory KioskMachineInfo({
    @Default(0) int kioskMachineId,
    @Default('') String uniqueKey,
    @Default(0) int kioskEventId,
    @Default('') String cardTerminalId,
    @Default(false) bool isUnderMaintenance,
    @Default(0) int eventId,
    @Default(0) int echoId,
    @Default(0.0) double photoCardPrice,
    @Default('') String printedEventName,
    @Default(false) bool isExpose,
    @Default('') String cardMaterialType,
    @Default(false) bool printableWithoutEmbed,
    @Default(false) bool isAutoEmbed,
    @Default('') String startDate,
    @Default('') String endDate,
    @Default('') String description,
    @Default('') String organizer,
    @Default('') String eventType,
    @Default('') String machineType,
    @Default('') String mainPosterImageUrl,
    @Default('') String coverImageUrl,
    @Default('') String previewImageUrl,
    @Default('') String detailImageUrl,
    @Default(0) int kioskDesignId,
    @Default('#000000') String mainButtonColor,
    @Default('#FFFFFF') String buttonTextColor,
    @Default('#CCCCCC') String keyPadColor,
    @Default('#000000') String couponTextColor,
    @Default('#000000') String mainTextColor,
    @Default('#000000') String popupButtonColor,
    @Default('') String topBannerUrl,
    @Default('') String mainImageUrl,
    @Default('#000000') String progressBarStartColor,
    @Default('#000000') String progressBarEndColor,
  }) = _KioskMachineInfo;

  factory KioskMachineInfo.fromJson(Map<String, dynamic> json) =>
      _$KioskMachineInfoFromJson(json);
}

extension KioskMachineInfoX on KioskMachineInfo {
  bool get isSuwon => kioskMachineId == 2 || kioskMachineId == 3;
}
