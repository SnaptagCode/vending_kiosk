import 'dart:developer';

import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vending_kiosk/core/common/constants/alert_key.dart';
import 'package:vending_kiosk/core/data/models/entities/slack_log_template.dart';
import 'package:vending_kiosk/core/data/repositories/kiosk_repository.dart';
import 'package:vending_kiosk/core/providers/version_notifier.dart';
import 'package:vending_kiosk/presentation/core/card_count_provider.dart';
import 'package:vending_kiosk/presentation/kiosk_shell/kiosk_info_service.dart';
import 'package:vending_kiosk/presentation/setup/alert_definition_provider.dart';

/// 서버 API POST /v1/internal/slack-alert 로 Slack 알림 전송 (type + message)
class SlackLogService {
  static final SlackLogService _instance = SlackLogService._internal();
  factory SlackLogService() => _instance;
  SlackLogService._internal();

  late ProviderContainer _container;
  List<String>? _excludedPaymentKeywords;

  Future<List<String>> _loadExcludedKeywords() async {
    if (_excludedPaymentKeywords != null) return _excludedPaymentKeywords!;
    try {
      final content = await rootBundle.loadString('assets/config/payment_broadcast_exclusions.txt');
      _excludedPaymentKeywords = content
          .split('\n')
          .map((line) => line.trim())
          .where((line) => line.isNotEmpty && !line.startsWith('#'))
          .toList();
    } catch (e) {
      log('❌ payment_broadcast_exclusions.txt 로드 실패: $e');
      _excludedPaymentKeywords = [];
    }
    return _excludedPaymentKeywords!;
  }

  Future<bool> _isPaymentDescriptionExcluded(String description) async {
    final keywords = await _loadExcludedKeywords();
    return keywords.any((keyword) => description.contains(keyword));
  }

  void init(ProviderContainer container) {
    _container = container;
    sendLogToSlack("🚀 Flutter App Started!");
  }

  Future<void> _sendSlackAlert(String type, String message) async {
    if (message.isEmpty) {
      log("❌ Slack 알림 메시지가 없습니다.");
      return;
    }
    try {
      final machineId = _container.read(kioskInfoServiceProvider)?.kioskMachineId ?? 0;
      await _container.read(kioskRepositoryProvider).sendSlackAlert(machineId: machineId, type: type, message: message);
    } catch (e) {
      log("❌ Slack 알림 API 오류: $e");
    }
  }

  Future<void> sendErrorLogToSlack(String message) async {
    final type = kDebugMode ? 'test_error_log' : 'error_log';
    // await _sendSlackAlert('test_error_log', message);
    await _sendSlackAlert(type, message);
  }

  Future<void> sendLogToSlack(String message) async {
    final type = kDebugMode ? 'test_log' : 'log';
    // await _sendSlackAlert('test_log', message);
    await _sendSlackAlert(type, message);
  }

  Future<void> _sendServiceAlarmToSlack(String message) async {
    final type = kDebugMode ? 'test_service' : 'service';
    // await _sendSlackAlert('test_service', message);
    await _sendSlackAlert(type, message);
  }

  Future<void> _sendVendingToSlack(String message) async {
    await _sendSlackAlert('vending', message);
  }

  // 1) 객체 만드는 함수 LogState
  // 2) 분기 처리 하는 함수 key, LogState. 결제 sendBraas
  // 3) buildSlackAlertMessage 실행 LogState

  Future<SlackLogTemplate> createSlackLogTemplate(
    String? errorKey,
  ) async {
    final definitions = _container.read(alertDefinitionProvider);
    final def = definitions.firstWhereOrNull((e) => e.key == errorKey);
    final kioskInfo = _container.read(kioskInfoServiceProvider);
    final version = _container.read(versionStateProvider).currentVersion;
    final eventType = kioskInfo?.eventType ?? "-";

    final serviceNameMap = {
      "SUF": "수원FC",
      "SEF": "서울 이랜드 FC",
      "KEEFO": "성수 B'Day",
      "AGFC": "안산그리너스FC",
      "HWEG": "한화이글스"
    };

    final serviceName = serviceNameMap[eventType] ?? '기타';

    return def != null && errorKey != null
        ? SlackLogTemplate(
            key: errorKey,
            category: def.category,
            title: def.title,
            serviceName: serviceName,
            appVersion: version,
            guideText: def.guideText,
            guideUrl: def.guideUrl,
            description: def.description,
            kioskMachineInfo: kioskInfo)
        : SlackLogTemplate(
            key: '',
            category: '',
            title: '',
            serviceName: serviceName,
            appVersion: version,
            description: '',
            kioskMachineInfo: kioskInfo);
  }

  Future<void> sendInspectionEndBroadcastLogToSlack(String errorKey) async {
    final slackLogTemplate = await createSlackLogTemplate(errorKey);
    final cardCount = _container.read(cardCountProvider);

    if (slackLogTemplate.category.isNotEmpty) {
      final kioskInfo = slackLogTemplate.kioskMachineInfo;
      final eventName = kioskInfo?.printedEventName ?? "-";
      // final printLog = _container.read(printerLogProvider);
      // final printerheadTemp = printLog?.heaterTemperature ?? 0;
      // final printerheadTempString = printerheadTemp != 0 ? (printerheadTemp / 100).toStringAsFixed(2) : "알 수 없음";

      String description;

      description = '''
${slackLogTemplate.description}

- 불러온 이벤트 : $eventName
- 프린터 연결 상태 : 정상
- 결제 단말기 연결 상태 : 정상
''';

      final message = buildSlackAlertMessage(
        slackLogTemplate: slackLogTemplate.copyWith(description: description),
        cardCount: cardCount.currentCount,
      );

      await _sendServiceAlarmToSlack(message);
    }
  }

  Future<void> sendCrashRecoveryBroadcastLogToSlack(
    String errorKey, {
    required DateTime lastBeat,
    required Duration downtime,
  }) async {
    final slackLogTemplate = await createSlackLogTemplate(errorKey);
    if (slackLogTemplate.category.isEmpty) return;

    final cardCount = _container.read(cardCountProvider);
    final eventName = slackLogTemplate.kioskMachineInfo?.printedEventName ?? "-";

    final description = '''
${slackLogTemplate.description}

- 마지막 신호 : ${lastBeat.toString().split('.').first}
- 멈춘 시간 : ${downtime.inSeconds}초
- 불러온 이벤트 : $eventName
- 결제 단말기 연결 상태 : 정상
''';

    final message = buildSlackAlertMessage(
      slackLogTemplate: slackLogTemplate.copyWith(description: description),
      cardCount: cardCount.currentCount,
    );

    await _sendServiceAlarmToSlack(message);
  }

  Future<void> sendPaymentBroadcastLogToSlak(String errorKey, {required String paymentDescription}) async {
    if (await _isPaymentDescriptionExcluded(paymentDescription)) return;
    var slackLogTemplate = await createSlackLogTemplate(errorKey);

    // 환불 실패 알림은 서버 category 설정과 무관하게 항상 warning(🟡)으로 강제
    if (errorKey == InfoKey.paymentRefundFail.key) {
      slackLogTemplate = slackLogTemplate.copyWith(category: 'warning');
    }

    if (slackLogTemplate.category.isNotEmpty) {
      String description;

      description = '''
${slackLogTemplate.description}
            
- $paymentDescription''';

      final message = buildSlackAlertMessage(slackLogTemplate: slackLogTemplate.copyWith(description: description));

      await _sendServiceAlarmToSlack(message);
    }
  }

  Future<void> sendPeriodicLogBroadcastLogToSlack() async {
    final slackLogTemplate = await createSlackLogTemplate(null);
    final machineId = slackLogTemplate.kioskMachineInfo?.kioskMachineId ?? 0;

    if (machineId != 0) {
      final cardCount = _container.read(cardCountProvider);
      String description;
      description = '''
- 카드 수량 : ${cardCount.currentCount} / ${cardCount.initialCount}
''';

      final message = buildSlackAlertMessage(
          slackLogTemplate: slackLogTemplate.copyWith(title: '프린트 상태', category: 'info', description: description));

      await _sendServiceAlarmToSlack(message);
    }
  }

  Future<void> sendBroadcastLogToSlack(String errorKey) async {
    final slackLogTemplate = await createSlackLogTemplate(errorKey);
    final cardCount = _container.read(cardCountProvider);

    if (slackLogTemplate.category.isNotEmpty) {
      final message = buildSlackAlertMessage(
        slackLogTemplate: slackLogTemplate,
        cardCount: cardCount.currentCount,
      );

      await _sendServiceAlarmToSlack(message);
    }
  }

  String buildSlackAlertMessage({
    required SlackLogTemplate slackLogTemplate,
    int? cardCount,
  }) {
    final cardInfo = '''
${cardCount == 0 ? "- 단면 -> 양면 모드" : "- 단면 모드 설정\n- 단면 설정 개수 : $cardCount개"}
      ''';

    final emojiMap = {
      'error': '🔴',
      'warning': '🟡',
      'info': '🟢',
    };
    final emoji = emojiMap[slackLogTemplate.category.toLowerCase()] ?? 'ℹ️';

    final formattedTitle = (slackLogTemplate.title == "점검 완료" || slackLogTemplate.title == "점검 시작")
        ? '🟢  *${slackLogTemplate.title}*'
        : '$emoji  *${slackLogTemplate.title}*';

    final guidePart = slackLogTemplate.guideText != null
        ? "[${slackLogTemplate.guideUrl != null ? '<${slackLogTemplate.guideUrl}|${slackLogTemplate.guideText}>' : slackLogTemplate.guideText}]"
        : '';

    return '''
$formattedTitle
───────────────────
Kiosk: ${slackLogTemplate.kioskMachineInfo?.kioskMachineName.isNotEmpty == true ? '${slackLogTemplate.kioskMachineInfo!.kioskMachineName} (${slackLogTemplate.kioskMachineInfo!.kioskMachineId})' : slackLogTemplate.kioskMachineInfo?.kioskMachineId ?? 0}  /  ${slackLogTemplate.appVersion}
업체(구단): ${slackLogTemplate.serviceName}
───────────────────
${slackLogTemplate.description}
${slackLogTemplate.title == "카드 인쇄 모드 변경" ? cardInfo : ""}
$guidePart
''';
  }

  Future<void> sendArbitraryPrintFailLogToSlack() async {
    final kioskInfo = _container.read(kioskInfoServiceProvider);
    final version = _container.read(versionStateProvider).currentVersion;

    final message = '''🔴  임의출력/재출력에 실패했습니다. 카드 수량을 확인해주세요.
───────────────────
Kiosk: ${kioskInfo?.kioskMachineName.isNotEmpty == true ? '${kioskInfo?.kioskMachineName} (${kioskInfo?.kioskMachineId})' : kioskInfo?.kioskMachineId ?? 0}  /  $version
''';

    await _sendVendingToSlack(message);
  }

  /// 요청한 카드 장수보다 적게 배출되었을 때 브로드캐스트 알림
  Future<void> sendCardDispenseShortfallLogToSlack({
    required int requestedCount,
    required int dispensedCount,
    String? reason,
  }) async {
    final kioskInfo = _container.read(kioskInfoServiceProvider);
    final version = _container.read(versionStateProvider).currentVersion;
    final shortage = requestedCount - dispensedCount;
    final cleanedReason = reason?.replaceFirst(RegExp(r'^Exception:\s*'), '').trim();
    // 한글 도메인 메시지는 그대로 공지 — raw 예외 원문(영문 등)은 관리자용 사유로 매핑하고 원문은 error_log 채널로 발송
    String? displayReason = cleanedReason;
    if (cleanedReason != null && cleanedReason.isNotEmpty && !RegExp(r'[가-힣]').hasMatch(cleanedReason)) {
      displayReason = _dispenseShortfallReasonFor(cleanedReason);
      sendErrorLogToSlack(
          '[MachineId: ${kioskInfo?.kioskMachineId ?? 0}] 카드 배출 수량 부족(요청 $requestedCount장/배출 $dispensedCount장) 사유 원문: $cleanedReason');
    }
    final reasonLine = displayReason?.isNotEmpty == true ? '\n- 사유 : $displayReason' : '';

    final message = '''🔴  *카드 배출 수량 부족*
───────────────────
Kiosk: ${kioskInfo?.kioskMachineName.isNotEmpty == true ? '${kioskInfo?.kioskMachineName} (${kioskInfo?.kioskMachineId})' : kioskInfo?.kioskMachineId ?? 0}  /  $version
───────────────────
요청한 카드 수량보다 적게 배출되었습니다.

- 요청 수량 : $requestedCount장
- 배출 수량 : $dispensedCount장
- 부족 수량 : *$shortage장*$reasonLine
''';

    await _sendServiceAlarmToSlack(message);
  }

  /// raw 예외 원문을 관리자가 이해할 수 있는 배출 실패 사유로 매핑
  String _dispenseShortfallReasonFor(String rawReason) {
    final lower = rawReason.toLowerCase();
    if (lower.contains('dioexception')) {
      return '서버 통신 오류 (배출기 고장 아님)';
    }
    if (lower.contains('printed photo card ids length')) {
      return '주문 정보 불일치 (주문 카드 수 ≠ 요청 수량)';
    }
    if (lower.contains('serial port') || lower.contains('failed to write') || lower.contains('withtech')) {
      return '배출기 통신 오류 (연결 상태 확인 필요)';
    }
    if (lower.contains('timeout')) {
      return '배출기 응답 시간 초과';
    }
    return '확인 필요 (개발자 문의)';
  }

  Future<void> sendCardDispenserErrorLogToSlack(String msg) async {
    final kioskInfo = _container.read(kioskInfoServiceProvider);
    final version = _container.read(versionStateProvider).currentVersion;
    final cleanedMsg = msg.replaceFirst(RegExp(r'^Exception:\s*'), '');

    final title = '''🔴 카드 배출기 에러
───────────────────
Kiosk: ${kioskInfo?.kioskMachineName.isNotEmpty == true ? '${kioskInfo?.kioskMachineName} (${kioskInfo?.kioskMachineId})' : kioskInfo?.kioskMachineId ?? 0}  /  $version
───────────────────
$cleanedMsg
''';

    await _sendVendingToSlack(title);
  }
}
