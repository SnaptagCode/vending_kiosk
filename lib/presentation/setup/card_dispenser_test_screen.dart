import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:vending_kiosk/core/common/constants/image_paths.dart';
import 'package:vending_kiosk/core/common/extensions/build_context.dart';
import 'package:vending_kiosk/core/common/logger/logger_service.dart';
import 'package:vending_kiosk/core/common/logger/slack_log_service.dart';
import 'package:vending_kiosk/core/common/sound/sound_manager.dart';
import 'package:vending_kiosk/core/services/card_dispenser_service.dart';
import 'package:vending_kiosk/core/services/card_dispenser_manager.dart';
import 'package:vending_kiosk/core/ui/widget/dialog_helper.dart';
import 'package:vending_kiosk/presentation/setup/card_dispenser_connect_state.dart';
import 'package:vending_kiosk/presentation/setup/models/error_log_entry.dart';

class CardDispenserTestScreen extends ConsumerStatefulWidget {
  const CardDispenserTestScreen({super.key});

  @override
  ConsumerState<CardDispenserTestScreen> createState() => _CardDispenserTestScreenState();
}

class _CardDispenserTestScreenState extends ConsumerState<CardDispenserTestScreen> {
  String _statusMessage = '대기 중';
  String? _errorMessage;
  bool _isProcessing = false;
  final List<ErrorLogEntry> _errorLogs = [];
  int _timeoutSeconds = 10;
  DateTime? _lastCommunicationTime;

  @override
  Widget build(BuildContext context) {
    final serviceState = ref.watch(cardDispenserServiceProvider);
    final connectState = ref.watch(cardDispenserConnectProvider);

    final isConnected = connectState == CardDispenserConnectState.connected;

    return Theme(
      data: Theme.of(context).copyWith(
        textTheme: Theme.of(context).textTheme.apply(
              fontFamily: 'Pretendard',
            ),
      ),
      child: Scaffold(
        backgroundColor: Color(0xFFF2F2F2),
        appBar: AppBar(
          centerTitle: false,
          leading: IconButton(
            icon: SvgPicture.asset(
              SnaptagSvg.arrowBack,
              width: 44.w,
            ),
            onPressed: () async {
              await SoundManager().playSound();
              Navigator.of(context).pop();
            },
          ),
          title: Text(
            '카드 배출기 테스트',
            style: context.typography.kioskBody1B,
          ),
        ),
        body: Container(
          decoration: BoxDecoration(
            image: DecorationImage(
              image: AssetImage(SnaptagImages.setupBackground),
              fit: BoxFit.fill,
            ),
          ),
          child: SingleChildScrollView(
            padding: EdgeInsets.all(40.w),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 연결 정보 섹션
                _buildInfoSection(
                  title: '연결 정보',
                  children: [
                    _buildInfoRow('포트', CardDispenserManager.connectedPortName ?? '자동 감지 대기 중'),
                    _buildInfoRow('감지 방식', '자동 감지'),
                    _buildInfoRow(
                      '연결 상태',
                      _getConnectionStatusText(connectState),
                      statusColor: _getConnectionStatusColor(connectState),
                    ),
                    _buildInfoRow(
                      '서비스 상태',
                      _getServiceStateText(serviceState),
                      statusColor: _getServiceStateColor(serviceState),
                    ),
                  ],
                ),
                SizedBox(height: 30.h),

                // 상태 메시지
                _buildInfoSection(
                  title: '상태 메시지',
                  children: [
                    Container(
                      width: double.infinity,
                      padding: EdgeInsets.all(20.w),
                      decoration: BoxDecoration(
                        color: Color(0xFFF9F9F9),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        _statusMessage,
                        style: context.typography.kioskBody2B.copyWith(
                          color: Color(0xFF1C1C1C),
                        ),
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 20.h),

                // 에러 메시지
                if (_errorMessage != null) ...[
                  _buildInfoSection(
                    title: '에러 정보',
                    children: [
                      Container(
                        width: double.infinity,
                        padding: EdgeInsets.all(20.w),
                        decoration: BoxDecoration(
                          color: Color(0xFFFFEBEE),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          _errorMessage!,
                          style: context.typography.kioskBody2B.copyWith(
                            color: Colors.red,
                          ),
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: 20.h),
                ],

                // 연결 제어 버튼
                _buildInfoSection(
                  title: '연결 제어',
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: _buildActionButton(
                            label: '연결 테스트',
                            icon: SnaptagSvg.refresh,
                            onPressed: _isProcessing ? null : _testConnection,
                          ),
                        ),
                        SizedBox(width: 20.w),
                        Expanded(
                          child: _buildActionButton(
                            label: '상태 확인',
                            icon: SnaptagSvg.refresh,
                            onPressed: _isProcessing || !isConnected ? null : _checkStatus,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                SizedBox(height: 30.h),

                // 카드 배출 테스트
                _buildInfoSection(
                  title: '카드 배출 테스트',
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: _buildDispenseButton(
                            count: 1,
                            enabled: !_isProcessing && isConnected,
                          ),
                        ),
                        SizedBox(width: 20.w),
                        Expanded(
                          child: _buildDispenseButton(
                            count: 3,
                            enabled: !_isProcessing && isConnected,
                          ),
                        ),
                        SizedBox(width: 20.w),
                        Expanded(
                          child: _buildDispenseButton(
                            count: 5,
                            enabled: !_isProcessing && isConnected,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                SizedBox(height: 30.h),

                // 에러 핸들링 테스트
                _buildInfoSection(
                  title: '에러 핸들링 테스트',
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: _buildActionButton(
                            label: '에러 정보 조회',
                            icon: SnaptagSvg.error,
                            onPressed: _isProcessing || !isConnected ? null : _getErrorInfo,
                          ),
                        ),
                        SizedBox(width: 20.w),
                        Expanded(
                          child: _buildActionButton(
                            label: '연결 해제',
                            icon: SnaptagSvg.off,
                            onPressed: _isProcessing || !isConnected ? null : _disconnect,
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: 15.h),
                    Row(
                      children: [
                        Expanded(
                          child: _buildActionButton(
                            label: '타임아웃 테스트',
                            icon: SnaptagSvg.refresh,
                            onPressed: _isProcessing || !isConnected ? null : _timeoutTest,
                          ),
                        ),
                        SizedBox(width: 20.w),
                        Expanded(
                          child: _buildActionButton(
                            label: '로그 전송 테스트',
                            icon: SnaptagSvg.success,
                            onPressed: _isProcessing ? null : _testLogTransmission,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                SizedBox(height: 30.h),

                // 에러 로그 히스토리
                if (_errorLogs.isNotEmpty) ...[
                  _buildInfoSection(
                    title: '에러 로그 히스토리 (최근 ${_errorLogs.length}개)',
                    children: [
                      Container(
                        constraints: BoxConstraints(maxHeight: 300.h),
                        child: ListView.separated(
                          shrinkWrap: true,
                          itemCount: _errorLogs.length,
                          separatorBuilder: (context, index) => Divider(height: 1),
                          itemBuilder: (context, index) {
                            final log = _errorLogs[_errorLogs.length - 1 - index];
                            return _buildErrorLogItem(log);
                          },
                        ),
                      ),
                      SizedBox(height: 15.h),
                      SizedBox(
                        width: double.infinity,
                        child: TextButton(
                          onPressed: () {
                            setState(() {
                              _errorLogs.clear();
                            });
                          },
                          style: TextButton.styleFrom(
                            foregroundColor: Colors.red,
                          ),
                          child: Text(
                            '로그 전체 삭제',
                            style: context.typography.kioskBody2B.copyWith(
                              color: Colors.red,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: 30.h),
                ],

                // 복구 가이드
                if (_errorMessage != null) ...[
                  _buildInfoSection(
                    title: '복구 가이드',
                    children: [
                      _buildRecoveryGuide(_errorMessage!),
                    ],
                  ),
                  SizedBox(height: 30.h),
                ],

                // 통신 상태
                _buildInfoSection(
                  title: '통신 상태',
                  children: [
                    _buildInfoRow(
                      '타임아웃 설정',
                      '$_timeoutSeconds초',
                    ),
                    _buildInfoRow(
                      '마지막 통신',
                      _lastCommunicationTime != null
                          ? '${_lastCommunicationTime!.hour.toString().padLeft(2, '0')}:'
                              '${_lastCommunicationTime!.minute.toString().padLeft(2, '0')}:'
                              '${_lastCommunicationTime!.second.toString().padLeft(2, '0')}'
                          : '없음',
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildInfoSection({
    required String title,
    required List<Widget> children,
  }) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(30.w),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Color(0xFFE6E8EB),
          width: 2,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: context.typography.kioskBody1B.copyWith(
              color: Color(0xFF1C1C1C),
            ),
          ),
          SizedBox(height: 20.h),
          ...children,
        ],
      ),
    );
  }

  Widget _buildInfoRow(String label, String value, {Color? statusColor}) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 8.h),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: context.typography.kioskBody2B.copyWith(
              color: Color(0xFF666666),
            ),
          ),
          Text(
            value,
            style: context.typography.kioskBody2B.copyWith(
              color: statusColor ?? Color(0xFF1C1C1C),
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButton({
    required String label,
    required String icon,
    VoidCallback? onPressed,
  }) {
    final isEnabled = onPressed != null;
    return SizedBox(
      height: 80.h,
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: isEnabled ? Colors.black : Color(0xFFD5D5D5),
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SvgPicture.asset(
              icon,
              width: 24.w,
              height: 24.w,
              colorFilter: ColorFilter.mode(
                Colors.white,
                BlendMode.srcIn,
              ),
            ),
            SizedBox(width: 10.w),
            Text(
              label,
              style: TextStyle(
                fontSize: 24.sp,
                fontWeight: FontWeight.w600,
                color: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDispenseButton({
    required int count,
    required bool enabled,
  }) {
    return SizedBox(
      height: 120.h,
      child: ElevatedButton(
        onPressed: enabled ? () => _testDispense(count) : null,
        style: ElevatedButton.styleFrom(
          backgroundColor: enabled ? Color(0xFF316FFF) : Color(0xFFD5D5D5),
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              '$count장',
              style: TextStyle(
                fontSize: 32.sp,
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
            ),
            SizedBox(height: 8.h),
            Text(
              '배출',
              style: TextStyle(
                fontSize: 20.sp,
                fontWeight: FontWeight.w500,
                color: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _getConnectionStatusText(CardDispenserConnectState state) {
    return switch (state) {
      CardDispenserConnectState.connected => '연결됨',
      CardDispenserConnectState.disconnected => '연결 안 됨',
      CardDispenserConnectState.setupInComplete => '설정 중',
      CardDispenserConnectState.pending => '대기 중',
    };
  }

  Color _getConnectionStatusColor(CardDispenserConnectState state) {
    return switch (state) {
      CardDispenserConnectState.connected => Colors.green,
      CardDispenserConnectState.disconnected => Colors.red,
      CardDispenserConnectState.setupInComplete => Colors.orange,
      CardDispenserConnectState.pending => Colors.grey,
    };
  }

  String _getServiceStateText(CardDispenserServiceState state) {
    return state.when(
      idle: () => '대기',
      connecting: () => '연결 중',
      ready: () => '준비됨',
      dispensing: (count) => '$count장 배출 중',
      error: (msg) => '오류',
    );
  }

  Color _getServiceStateColor(CardDispenserServiceState state) {
    return state.when(
      idle: () => Color(0xFF666666),
      connecting: () => Colors.orange,
      ready: () => Colors.green,
      dispensing: (_) => Colors.blue,
      error: (_) => Colors.red,
    );
  }

  Future<void> _testConnection() async {
    await SoundManager().playSound();

    setState(() {
      _isProcessing = true;
      _statusMessage = '포트 자동 감지 중...';
      _errorMessage = null;
    });

    try {
      final service = ref.read(cardDispenserServiceProvider.notifier);
      final detected = await service.autoDetectPort();

      if (detected == null) {
        throw Exception('카드 배출기를 찾을 수 없습니다. 케이블 연결을 확인하세요.');
      }

      setState(() {
        _statusMessage = '연결 성공 (${detected.port})';
        _isProcessing = false;
        _lastCommunicationTime = DateTime.now();
      });

      ref.read(cardDispenserConnectProvider.notifier).update(
            CardDispenserConnectState.connected,
          );

      await DialogHelper.showSetupDialog(
        context,
        title: '연결 성공',
        content: '카드 배출기가 정상적으로 연결되었습니다.\n포트: ${detected.port}',
      );
    } catch (e) {
      logger.e('Connection test failed', error: e);
      _addErrorLog('연결 테스트', e.toString());
      setState(() {
        _statusMessage = '연결 테스트 실패';
        _errorMessage = e.toString();
        _isProcessing = false;
      });

      ref.read(cardDispenserConnectProvider.notifier).update(
            CardDispenserConnectState.disconnected,
          );

      await DialogHelper.showSetupDialog(
        context,
        title: '연결 실패',
        content: '카드 배출기 연결에 실패했습니다.\n\n$e',
      );
    }
  }

  Future<void> _checkStatus() async {
    await SoundManager().playSound();

    setState(() {
      _isProcessing = true;
      _statusMessage = '상태 확인 중...';
      _errorMessage = null;
    });

    try {
      // CardDispenserManager 직접 사용
      final manager = await CardDispenserManager.getInstance();
      final status = await manager.getStatus();
      final error = await manager.getError();

      setState(() {
        _statusMessage = '상태: $status';
        if (error.description != null) {
          _errorMessage = '에러 코드: ${error.errorCode}, 설명: ${error.description}';
        }
        _isProcessing = false;
        _lastCommunicationTime = DateTime.now();
      });

      await DialogHelper.showSetupDialog(
        context,
        title: '상태 확인',
        content: '상태: $status\n에러: ${error.description ?? "없음"}',
      );
    } catch (e) {
      logger.e('Status check failed', error: e);
      _addErrorLog('상태 확인', e.toString());
      setState(() {
        _statusMessage = '상태 확인 실패';
        _errorMessage = e.toString();
        _isProcessing = false;
      });

      await DialogHelper.showSetupDialog(
        context,
        title: '상태 확인 실패',
        content: e.toString(),
      );
    }
  }

  Future<void> _testDispense(int count) async {
    await SoundManager().playSound();

    final confirmed = await DialogHelper.showSetupDialog(
      context,
      title: '카드 배출',
      content: '$count장의 카드를 배출하시겠습니까?',
      showCancelButton: true,
    );

    if (!confirmed) return;

    setState(() {
      _isProcessing = true;
      _statusMessage = '$count장 배출 중...';
      _errorMessage = null;
    });

    try {
      final service = ref.read(cardDispenserServiceProvider.notifier);
      await service.dispenseAndWait(count: count);

      setState(() {
        _statusMessage = '$count장 배출 완료!';
        _isProcessing = false;
        _lastCommunicationTime = DateTime.now();
      });

      await DialogHelper.showSetupDialog(
        context,
        title: '배출 완료',
        content: '$count장의 카드가 정상적으로 배출되었습니다.',
      );
    } catch (e) {
      logger.e('Dispense test failed', error: e);
      _addErrorLog('카드 배출', e.toString());
      setState(() {
        _statusMessage = '카드 배출 실패';
        _errorMessage = e.toString();
        _isProcessing = false;
      });

      await DialogHelper.showSetupDialog(
        context,
        title: '배출 실패',
        content: '카드 배출에 실패했습니다.\n\n$e',
      );
    }
  }

  Future<void> _getErrorInfo() async {
    await SoundManager().playSound();

    setState(() {
      _isProcessing = true;
      _statusMessage = '에러 정보 조회 중...';
    });

    try {
      final manager = await CardDispenserManager.getInstance();
      final error = await manager.getError();

      setState(() {
        _statusMessage = '에러 정보 조회 완료';
        _isProcessing = false;
        _lastCommunicationTime = DateTime.now();
      });

      if (error.description == null) {
        await DialogHelper.showSetupDialog(
          context,
          title: '에러 없음',
          content: '현재 발생한 에러가 없습니다.',
        );
      } else {
        _addErrorLog('에러 조회', '코드: ${error.errorCode}, 설명: ${error.description}', error.errorCode);
        setState(() {
          _errorMessage = '에러 코드: ${error.errorCode}\n설명: ${error.description}';
        });

        await DialogHelper.showSetupDialog(
          context,
          title: '에러 정보',
          content: '에러 코드: ${error.errorCode}\n설명: ${error.description}',
        );
      }
    } catch (e) {
      logger.e('Get error info failed', error: e);
      _addErrorLog('에러 정보 조회', e.toString());
      setState(() {
        _statusMessage = '에러 정보 조회 실패';
        _errorMessage = e.toString();
        _isProcessing = false;
      });

      await DialogHelper.showSetupDialog(
        context,
        title: '조회 실패',
        content: e.toString(),
      );
    }
  }

  Future<void> _disconnect() async {
    await SoundManager().playSound();

    final confirmed = await DialogHelper.showSetupDialog(
      context,
      title: '연결 해제',
      content: '카드 배출기 연결을 해제하시겠습니까?\n에러 복구 테스트를 위해 사용됩니다.',
      showCancelButton: true,
    );

    if (!confirmed) return;

    setState(() {
      _isProcessing = true;
      _statusMessage = '연결 해제 중...';
      _errorMessage = null;
    });

    try {
      // 서비스를 idle 상태로 변경
      ref.read(cardDispenserConnectProvider.notifier).update(
            CardDispenserConnectState.disconnected,
          );

      setState(() {
        _statusMessage = '연결 해제됨';
        _isProcessing = false;
      });

      await DialogHelper.showSetupDialog(
        context,
        title: '연결 해제',
        content: '연결이 해제되었습니다.\n"연결 테스트"를 통해 재연결할 수 있습니다.',
      );
    } catch (e) {
      logger.e('Disconnect failed', error: e);
      _addErrorLog('연결 해제', e.toString());
      setState(() {
        _statusMessage = '연결 해제 실패';
        _errorMessage = e.toString();
        _isProcessing = false;
      });
    }
  }

  Future<void> _timeoutTest() async {
    await SoundManager().playSound();

    // 타임아웃 시간 선택 다이얼로그
    final timeoutOptions = [3, 5, 10, 15, 30];
    final selectedTimeout = await showDialog<int>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('타임아웃 시간 선택'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: timeoutOptions.map((seconds) {
            return ListTile(
              title: Text('$seconds초'),
              onTap: () => Navigator.pop(context, seconds),
            );
          }).toList(),
        ),
      ),
    );

    if (selectedTimeout == null) return;

    setState(() {
      _timeoutSeconds = selectedTimeout;
      _isProcessing = true;
      _statusMessage = '타임아웃 테스트 중 (${selectedTimeout}초)...';
      _errorMessage = null;
    });

    try {
      final service = ref.read(cardDispenserServiceProvider.notifier);

      // 카드 1장 배출 with 커스텀 타임아웃
      await service.dispenseAndWait(
        count: 1,
        overallTimeout: Duration(seconds: selectedTimeout),
      );

      setState(() {
        _statusMessage = '타임아웃 테스트 성공 (${selectedTimeout}초 내 완료)';
        _isProcessing = false;
        _lastCommunicationTime = DateTime.now();
      });

      await DialogHelper.showSetupDialog(
        context,
        title: '테스트 성공',
        content: '${selectedTimeout}초 타임아웃 내에 작업이 완료되었습니다.',
      );
    } catch (e) {
      logger.e('Timeout test failed', error: e);
      _addErrorLog('타임아웃 테스트', '${selectedTimeout}초: ${e.toString()}');
      setState(() {
        _statusMessage = '타임아웃 테스트 실패';
        _errorMessage = e.toString();
        _isProcessing = false;
      });

      await DialogHelper.showSetupDialog(
        context,
        title: '테스트 실패',
        content: '타임아웃 또는 에러 발생:\n\n$e',
      );
    }
  }

  Future<void> _testLogTransmission() async {
    await SoundManager().playSound();

    setState(() {
      _isProcessing = true;
      _statusMessage = '슬랙 로그 전송 테스트 중...';
    });

    try {
      await SlackLogService().sendLogToSlack(
        '[카드배출기 테스트] 로그 전송 테스트 - ${DateTime.now()}',
      );

      setState(() {
        _statusMessage = '로그 전송 성공';
        _isProcessing = false;
      });

      await DialogHelper.showSetupDialog(
        context,
        title: '로그 전송 성공',
        content: '슬랙으로 테스트 로그가 전송되었습니다.',
      );
    } catch (e) {
      logger.e('Log transmission test failed', error: e);
      _addErrorLog('로그 전송', e.toString());
      setState(() {
        _statusMessage = '로그 전송 실패';
        _errorMessage = e.toString();
        _isProcessing = false;
      });

      await DialogHelper.showSetupDialog(
        context,
        title: '로그 전송 실패',
        content: '슬랙 로그 전송에 실패했습니다.\n\n$e',
      );
    }
  }

  void _addErrorLog(String type, String message, [String? errorCode]) {
    setState(() {
      _errorLogs.add(ErrorLogEntry(
        timestamp: DateTime.now(),
        type: type,
        message: message,
        errorCode: errorCode,
      ));

      // 최대 20개까지만 유지
      if (_errorLogs.length > 20) {
        _errorLogs.removeAt(0);
      }
    });
  }

  Widget _buildErrorLogItem(ErrorLogEntry log) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 10.h, horizontal: 5.w),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                log.type,
                style: context.typography.kioskBody2B.copyWith(
                  color: Color(0xFF1C1C1C),
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                log.formattedTime,
                style: context.typography.kioskBody2B.copyWith(
                  color: Color(0xFF999999),
                  fontSize: 18.sp,
                ),
              ),
            ],
          ),
          SizedBox(height: 5.h),
          Text(
            log.message,
            style: context.typography.kioskBody2B.copyWith(
              color: Color(0xFF666666),
              fontSize: 18.sp,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          if (log.errorCode != null) ...[
            SizedBox(height: 5.h),
            Text(
              '에러 코드: ${log.errorCode}',
              style: context.typography.kioskBody2B.copyWith(
                color: Colors.red,
                fontSize: 18.sp,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildRecoveryGuide(String errorMessage) {
    String guide = '알 수 없는 에러입니다.';

    if (errorMessage.contains('연결') || errorMessage.contains('connect')) {
      guide = '1. 시리얼 포트 케이블 연결을 확인하세요.\n'
          '2. 다른 프로그램이 포트를 사용 중인지 확인하세요.\n'
          '3. 배출기 전원을 껐다 켜보세요.\n'
          '4. 연결 테스트 버튼을 눌러 자동 감지를 다시 시도하세요.';
    } else if (errorMessage.contains('timeout') || errorMessage.contains('타임아웃')) {
      guide = '1. 배출기가 응답하지 않습니다.\n'
          '2. 배출기 내부에 카드가 걸렸는지 확인하세요.\n'
          '3. 타임아웃 시간을 늘려보세요.\n'
          '4. 배출기를 재시작하세요.';
    } else if (errorMessage.contains('통신') || errorMessage.contains('health check')) {
      guide = '1. 시리얼 통신이 불안정합니다.\n'
          '2. 케이블 연결 상태를 확인하세요.\n'
          '3. 프로토콜 설정(txUpperRxLower/txLowerRxLower)을 확인하세요.\n'
          '4. 연결을 해제하고 다시 연결하세요.';
    } else if (errorMessage.contains('배출') || errorMessage.contains('dispense')) {
      guide = '1. 카드 배출에 실패했습니다.\n'
          '2. 배출기에 카드가 충분한지 확인하세요.\n'
          '3. 배출구가 막혀있지 않은지 확인하세요.\n'
          '4. "에러 정보 조회"로 상세 에러를 확인하세요.';
    }

    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(20.w),
      decoration: BoxDecoration(
        color: Color(0xFFFFF3E0),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.orange),
      ),
      child: Text(
        guide,
        style: context.typography.kioskBody2B.copyWith(
          color: Color(0xFF1C1C1C),
          height: 1.5,
        ),
      ),
    );
  }
}
