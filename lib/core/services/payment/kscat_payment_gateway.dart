import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:vending_kiosk/core/common/logger/slack_log_service.dart';
import 'package:vending_kiosk/core/data/datasources/remote/payment_api_client.dart';
import 'package:vending_kiosk/core/data/models/request/kscat_device_request.dart';
import 'package:vending_kiosk/core/data/models/request/payment_request.dart';
import 'package:vending_kiosk/core/data/models/response/kscat_device_response.dart';
import 'package:vending_kiosk/core/data/models/response/payment_response.dart';
import 'package:vending_kiosk/core/domain/entities/invoice.dart';
import 'package:vending_kiosk/core/services/payment/payment_gateway.dart';
import 'package:vending_kiosk/presentation/kiosk_shell/kiosk_info_service.dart';

enum _TerminalState { busy, idle, noResponse }

class KscatPaymentGateway implements PaymentGateway {
  KscatPaymentGateway(
    this._client,
    this.ref, {
    this.checkTimeout = const Duration(seconds: 5),
    this.watchInterval = const Duration(seconds: 3),
    this.resultGrace = const Duration(seconds: 5),
    this.approveTimeout = const Duration(seconds: 60),
    this.cancelTimeout = const Duration(seconds: 60),
  });

  final PaymentApiClient _client;
  final Ref ref;
  final Duration checkTimeout;
  final Duration watchInterval;
  final Duration resultGrace;
  final Duration approveTimeout;
  final Duration cancelTimeout;

  String _getCallback() {
    final kioskMachineId = ref.read(kioskInfoServiceProvider)?.kioskMachineId;
    final formattedMachineId = kioskMachineId.toString().padLeft(2, '0');
    return 'jsonp200911MI$formattedMachineId';
  }

  @override
  Future<PaymentResponse> approve({
    required int totalAmount,
  }) async {
    final Invoice invoice = Invoice.calculate(totalAmount);
    final cardTerminalId = ref.read(kioskInfoServiceProvider)?.cardTerminalId;
    final request = PaymentRequest.approval(
      totalAmount: invoice.total.toString(),
      tax: invoice.taxAmount.toString(),
      supplyAmount: invoice.supplyAmount.toString(),
      terminalId: cardTerminalId ?? 'AT0416146A',
    );

    final machineId = ref.read(kioskInfoServiceProvider)?.kioskMachineId ?? 'unknown';
    SlackLogService().sendLogToSlack('*[MachineId: $machineId | KSCAT PaymentRequest]*\n ${request.serialize()}');

    return _approveWatched(request);
  }

  @override
  Future<KscatDeviceResponse> check() async {
    final request = KscatDeviceRequest(
      req: 'C0',
    );

    return _client.requestDeivce(_getCallback(), request.serialize(), timeout: checkTimeout);
  }

  @override
  Future<PaymentResponse> cancel({
    required int totalAmount,
    required String originalApprovalNo,
    required String originalApprovalDate,
  }) async {
    final Invoice invoice = Invoice.calculate(totalAmount);
    final cardTerminalId = ref.read(kioskInfoServiceProvider)?.cardTerminalId;
    final request = PaymentRequest.cancel(
      totalAmount: invoice.total.toString(),
      tax: invoice.taxAmount.toString(),
      supplyAmount: invoice.supplyAmount.toString(),
      originalApprovalNo: originalApprovalNo,
      originalApprovalDate: originalApprovalDate,
      terminalId: cardTerminalId ?? 'AT0416146A',
    );

    return _client.requestPayment(_getCallback(), request.serialize(), timeout: cancelTimeout);
  }

  Future<PaymentResponse> _approveWatched(PaymentRequest request) async {
    final httpClient = http.Client();
    final result = Completer<PaymentResponse>();

    void stop(String reason) {
      if (!result.isCompleted) result.completeError(TerminalResultUnknownException(reason));
    }

    _client.requestPayment(_getCallback(), request.serialize(), client: httpClient).then(
      (response) {
        if (!result.isCompleted) result.complete(response);
      },
      onError: (Object e, StackTrace s) => stop('결제 중 단말기 연결 끊김 ($e)'),
    );

    final deadline = Timer(approveTimeout, () => stop('결제 응답 ${approveTimeout.inSeconds}초 초과'));
    unawaited(_watch(result, stop));

    try {
      return await result.future;
    } finally {
      deadline.cancel();
      httpClient.close();
    }
  }

  Future<void> _watch(Completer<PaymentResponse> result, void Function(String reason) stop) async {
    final done = result.future.then((_) {}, onError: (_) {});

    while (!result.isCompleted) {
      await Future.any([done, Future.delayed(watchInterval)]);
      if (result.isCompleted) return;

      final state = await _probe();
      if (result.isCompleted) return;

      switch (state) {
        case _TerminalState.busy:
          continue;
        case _TerminalState.noResponse:
          stop('결제 중 단말기 응답 없음');
          return;
        case _TerminalState.idle:
          await Future.any([done, Future.delayed(resultGrace)]);
          stop('단말기 거래 종료 후 결제 결과 미수신');
          return;
      }
    }
  }

  Future<_TerminalState> _probe() async {
    try {
      final response = await check();
      return response.res == '1001' ? _TerminalState.idle : _TerminalState.busy;
    } catch (_) {
      return _TerminalState.noResponse;
    }
  }
}
