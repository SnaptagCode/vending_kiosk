import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:vending_kiosk/core/data/datasources/remote/payment_api_client.dart';
import 'package:vending_kiosk/core/data/models/response/kscat_device_response.dart';
import 'package:vending_kiosk/core/data/models/response/payment_response.dart';
import 'package:vending_kiosk/core/services/payment/kscat_payment_gateway.dart';
import 'package:vending_kiosk/core/services/payment/payment_gateway.dart';

enum Probe { busy, idle, hang }

class FakeKscat extends PaymentApiClient {
  Probe probe = Probe.busy;
  final approval = Completer<PaymentResponse>();
  int probes = 0;

  @override
  Future<PaymentResponse> requestPayment(String callback, String request,
      {http.Client? client, Duration? timeout}) {
    final f = approval.future;
    return timeout == null ? f : f.timeout(timeout);
  }

  @override
  Future<KscatDeviceResponse> requestDeivce(String callback, String request, {Duration? timeout}) async {
    probes++;
    switch (probe) {
      case Probe.busy:
        return const KscatDeviceResponse(res: '1003');
      case Probe.idle:
        return const KscatDeviceResponse(res: '1001');
      case Probe.hang:
        await Future<void>.delayed(timeout!);
        throw TimeoutException('C0', timeout);
    }
  }
}

const approved = PaymentResponse(res: '0000', respCode: '0000', approvalNo: '12345678');

void main() {
  late ProviderContainer container;
  late FakeKscat kscat;
  late KscatPaymentGateway gateway;

  setUp(() {
    container = ProviderContainer();
    kscat = FakeKscat();
    final provider = Provider(
      (ref) => KscatPaymentGateway(
        kscat,
        ref,
        checkTimeout: const Duration(milliseconds: 40),
        watchInterval: const Duration(milliseconds: 20),
        resultGrace: const Duration(milliseconds: 60),
        approveTimeout: const Duration(milliseconds: 400),
        cancelTimeout: const Duration(milliseconds: 100),
      ),
    );
    gateway = container.read(provider);
  });

  tearDown(() => container.dispose());

  Matcher unknown(String reason) =>
      throwsA(isA<TerminalResultUnknownException>().having((e) => e.reason, 'reason', contains(reason)));

  test('결제 중(1003)이면 기다렸다가 정상 응답을 그대로 돌려준다', () async {
    Timer(const Duration(milliseconds: 150), () => kscat.approval.complete(approved));
    final res = await gateway.approve(totalAmount: 1000);
    expect(res.res, '0000');
    expect(kscat.probes, greaterThan(2));
  });

  test('1003이 계속되면 최종 타임아웃에서 중단한다', () async {
    final sw = Stopwatch()..start();
    await expectLater(gateway.approve(totalAmount: 1000), unknown('초과'));
    expect(sw.elapsedMilliseconds, greaterThanOrEqualTo(400));
  });

  test('결제 중 단말기가 응답하지 않으면 최종 타임아웃 전에 중단한다', () async {
    kscat.probe = Probe.hang;
    final sw = Stopwatch()..start();
    await expectLater(gateway.approve(totalAmount: 1000), unknown('응답 없음'));
    expect(sw.elapsedMilliseconds, lessThan(400));
  });

  test('단말기가 거래 종료(1001)인데 결과가 안 오면 유예 후 중단한다', () async {
    kscat.probe = Probe.idle;
    final sw = Stopwatch()..start();
    await expectLater(gateway.approve(totalAmount: 1000), unknown('미수신'));
    expect(sw.elapsedMilliseconds, greaterThanOrEqualTo(80));
    expect(sw.elapsedMilliseconds, lessThan(400));
  });

  test('1001 직후 유예 시간 안에 결과가 오면 정상 처리한다', () async {
    kscat.probe = Probe.idle;
    Timer(const Duration(milliseconds: 40), () => kscat.approval.complete(approved));
    final res = await gateway.approve(totalAmount: 1000);
    expect(res.res, '0000');
  });

  test('결제 요청 후 연결이 끊기면 결과 모름으로 중단한다', () async {
    Timer(const Duration(milliseconds: 30),
        () => kscat.approval.completeError(http.ClientException('Connection closed before full header was received')));
    await expectLater(gateway.approve(totalAmount: 1000), unknown('연결 끊김'));
  });

  test('장치 확인은 단말기가 응답하지 않으면 타임아웃으로 실패한다', () async {
    kscat.probe = Probe.hang;
    await expectLater(gateway.check(), throwsA(isA<TimeoutException>()));
  });

  test('환불은 응답이 없으면 타임아웃으로 실패한다', () async {
    await expectLater(
      gateway.cancel(totalAmount: 1000, originalApprovalNo: '12345678', originalApprovalDate: '261007'),
      throwsA(isA<TimeoutException>()),
    );
  });
}
