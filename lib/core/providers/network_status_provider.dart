import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dio/dio.dart';
import 'package:vending_kiosk/core/common/logger/logger_service.dart';
import 'package:internet_connection_checker/internet_connection_checker.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'network_status_provider.g.dart';

/// 네트워크 연결 상태
enum NetworkStatus {
  /// 연결됨 - 인터넷에 정상적으로 연결됨
  connected,

  /// 연결 중 - 연결 시도 중
  connecting,

  /// 불안정 - 연결은 되지만 불안정함 (간헐적 연결 끊김)
  unstable,

  /// 연결 끊김 - 네트워크 연결이 없음
  disconnected,
}

/// 네트워크 연결 타입
enum NetworkType {
  wifi,
  mobile,
  ethernet,
  none,
}

/// 네트워크 상태 정보
class NetworkState {
  final NetworkStatus status;
  final NetworkType type;
  final bool hasInternet;
  final DateTime lastChecked;

  const NetworkState({
    required this.status,
    required this.type,
    required this.hasInternet,
    required this.lastChecked,
  });

  NetworkState copyWith({
    NetworkStatus? status,
    NetworkType? type,
    bool? hasInternet,
    DateTime? lastChecked,
  }) {
    return NetworkState(
      status: status ?? this.status,
      type: type ?? this.type,
      hasInternet: hasInternet ?? this.hasInternet,
      lastChecked: lastChecked ?? this.lastChecked,
    );
  }
}

@Riverpod(keepAlive: true)
class NetworkStatusNotifier extends _$NetworkStatusNotifier {
  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;
  StreamSubscription<InternetConnectionStatus>? _internetSubscription;
  Timer? _checkTimer;
  int _consecutiveFailures = 0;
  static const int _maxFailures = 3;
  // checkInterval을 30초로 설정: 기본값(수 초)이면 TCP 소켓을 너무 자주 열어
  // Dart 이벤트 루프를 포화시키고 exit() 블로킹 및 콘솔 렉을 유발함
  final _internetChecker = InternetConnectionChecker.createInstance(
    checkInterval: const Duration(seconds: 30),
    checkTimeout: const Duration(seconds: 5),
  );

  @override
  NetworkState build() {
    _startMonitoring();
    ref.onDispose(() {
      _connectivitySubscription?.cancel();
      _internetSubscription?.cancel();
      _checkTimer?.cancel();
    });
    return NetworkState(
      status: NetworkStatus.connecting,
      type: NetworkType.none,
      hasInternet: false,
      lastChecked: DateTime.now(),
    );
  }

  /// 네트워크 모니터링 시작
  void _startMonitoring() {
    // 초기 상태 확인
    _checkNetworkStatus();

    // 연결 타입 변경 감지
    _connectivitySubscription = Connectivity().onConnectivityChanged.listen(
      (List<ConnectivityResult> results) {
        _handleConnectivityChange(results);
      },
    );

    // 인터넷 연결 상태 변경 감지
    _internetSubscription = _internetChecker.onStatusChange.listen(
      (InternetConnectionStatus status) {
        _handleInternetStatusChange(status);
      },
    );

    // // 주기적으로 상태 확인 (5초마다)
    // _checkTimer = Timer.periodic(const Duration(seconds: 5), (_) {
    //   _checkNetworkStatus();
    // });
  }

  /// 네트워크 상태 확인
  Future<void> _checkNetworkStatus() async {
    try {
      final connectivityResults = await Connectivity().checkConnectivity();
      final hasInternet = await _internetChecker.hasConnection;

      _handleConnectivityChange(connectivityResults);
      _updateInternetStatus(hasInternet);
    } catch (e) {
      state = state.copyWith(
        status: NetworkStatus.disconnected,
        lastChecked: DateTime.now(),
      );
    }
  }

  /// 연결 타입 변경 처리
  void _handleConnectivityChange(List<ConnectivityResult> results) {
    NetworkType type = NetworkType.none;

    if (results.contains(ConnectivityResult.wifi)) {
      type = NetworkType.wifi;
    } else if (results.contains(ConnectivityResult.mobile)) {
      type = NetworkType.mobile;
    } else if (results.contains(ConnectivityResult.ethernet)) {
      type = NetworkType.ethernet;
    }

    state = state.copyWith(
      type: type,
      lastChecked: DateTime.now(),
    );

    // 연결 타입이 없으면 연결 끊김 상태
    if (type == NetworkType.none) {
      state = state.copyWith(
        status: NetworkStatus.disconnected,
        hasInternet: false,
      );
    }
  }

  /// 인터넷 연결 상태 변경 처리
  void _handleInternetStatusChange(InternetConnectionStatus status) {
    final hasInternet = status == InternetConnectionStatus.connected;
    _updateInternetStatus(hasInternet);
  }

  /// 인터넷 연결 상태 업데이트
  void _updateInternetStatus(bool hasInternet) {
    NetworkStatus newStatus;


    if (state.type == NetworkType.none) {
      newStatus = NetworkStatus.disconnected;
      _consecutiveFailures = 0;
    } else if (hasInternet) {
      _consecutiveFailures = 0;
      newStatus = NetworkStatus.connected;
    } else {
      _consecutiveFailures++;
      if (_consecutiveFailures >= _maxFailures) {
        newStatus = NetworkStatus.disconnected;
      } else if (_consecutiveFailures >= 2) {
        newStatus = NetworkStatus.unstable;
      } else {
        newStatus = NetworkStatus.connecting;
      }
    }


    state = state.copyWith(
      status: newStatus,
      hasInternet: hasInternet,
      lastChecked: DateTime.now(),
    );
  }

  bool isNetworkError(dynamic error) {
    return error is DioException &&
        (error.type == DioExceptionType.connectionTimeout ||
            error.type == DioExceptionType.receiveTimeout ||
            error.type == DioExceptionType.sendTimeout ||
            error.type == DioExceptionType.connectionError ||
            error.type == DioExceptionType.unknown);
  }

  /// 수동으로 네트워크 상태 새로고침
  Future<void> refresh() async {
    await _checkNetworkStatus();
  }
}
