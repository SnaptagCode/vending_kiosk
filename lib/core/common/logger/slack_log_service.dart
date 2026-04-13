import 'dart:developer';

import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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

    return def != null && errorKey != null
        ? SlackLogTemplate(
            key: errorKey,
            category: def.category,
            title: def.title,
            serviceName: kioskInfo?.printedEventName.isNotEmpty == true ? kioskInfo!.printedEventName : '-',
            appVersion: version,
            guideText: def.guideText,
            guideUrl: def.guideUrl,
            description: def.description,
            kioskMachineInfo: kioskInfo)
        : SlackLogTemplate(
            key: '',
            category: '',
            title: '',
            serviceName: kioskInfo?.printedEventName.isNotEmpty == true ? kioskInfo!.printedEventName : '-',
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

- 단면 카드 수량 : ${cardCount.currentCount} / ${cardCount.initialCount}
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

  Future<void> sendPaymentBroadcastLogToSlak(String errorKey, {required String paymentDescription}) async {
    final slackLogTemplate = await createSlackLogTemplate(errorKey);

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
eventName: ${slackLogTemplate.serviceName}
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
