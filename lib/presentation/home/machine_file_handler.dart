import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vending_kiosk/core/common/logger/slack_log_service.dart';
import 'package:vending_kiosk/core/common/machine_log/machine_file_service.dart';
import 'package:vending_kiosk/core/data/models/request/kiosk_log_request.dart';
import 'package:vending_kiosk/core/data/models/response/machine_maintenance_response.dart';
import 'package:vending_kiosk/core/data/repositories/kiosk_repository.dart';

final machineFileHandlerProvider = Provider((ref) {
  return MachineFileHandler(ref, const MachineFileService());
});

class MachineFileHandler {
  const MachineFileHandler(this._ref, this._fileService);

  final Ref _ref;
  final MachineFileService _fileService;

  Future<void> sendLogFiles(List<MachineLogItem> items, int machineId) async {
    for (final item in items) {
      await _sendLogFile(item.path, item.id, machineId);
    }
  }

  Future<void> _sendLogFile(String path, int logId, int machineId) async {
    final now = DateTime.now();
    final dateSuffix =
        '.${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}';
    final normalizedPath = path.replaceAll('/', r'\');
    final fileName = '${normalizedPath.split(r'\').last}$dateSuffix';

    final result = await _fileService.readFile(normalizedPath);

    switch (result.status) {
      case FileReadStatus.accessError:
        try {
          await _ref.read(kioskRepositoryProvider).sendKioskLog(
                KioskLogRequest.withLogId(
                    logId: logId, machineId: machineId, title: fileName, content: '경로 접근 실패: ${result.error}'),
                isError: true,
              );
        } catch (_) {
          SlackLogService().sendErrorLogToSlack(
            '*[MachineId: $machineId / LogId: $logId]* 경로 접근 실패 알림 전송 실패 ($path): ${result.error}',
          );
        }
      case FileReadStatus.notFound:
        try {
          await _ref.read(kioskRepositoryProvider).sendKioskLog(
                KioskLogRequest.withLogId(
                    logId: logId, machineId: machineId, title: fileName, content: '파일 없음: $path'),
                isError: true,
              );
        } catch (e) {
          SlackLogService().sendErrorLogToSlack(
            '*[MachineId: $machineId / LogId: $logId]* 파일 없음 알림 전송 실패 ($path): $e',
          );
        }
      case FileReadStatus.empty:
        await _ref.read(kioskRepositoryProvider).sendKioskLog(
              KioskLogRequest.withLogId(
                  logId: logId, machineId: machineId, title: fileName, content: '파일이 비어 있음: $path'),
              isError: true,
            );
      case FileReadStatus.readError:
        try {
          await _ref.read(kioskRepositoryProvider).sendKioskLog(
                KioskLogRequest.withLogId(
                    logId: logId, machineId: machineId, title: fileName, content: '파일 읽기 실패: ${result.error}'),
                isError: true,
              );
        } catch (_) {
          SlackLogService().sendErrorLogToSlack(
            '*[MachineId: $machineId / LogId: $logId]* 파일 읽기 실패 알림 전송 실패 ($path): ${result.error}',
          );
        }
      case FileReadStatus.success:
        final title = result.isDirectory ? '$fileName.zip' : fileName;
        try {
          await _ref.read(kioskRepositoryProvider).sendKioskLog(
                KioskLogRequest.withLogId(
                    logId: logId, machineId: machineId, title: title, content: result.content ?? ''),
                zipFile: result.zipBytes,
              );
        } catch (e) {
          SlackLogService().sendErrorLogToSlack(
            '*[MachineId: $machineId / LogId: $logId]* 로그 전송 실패 ($path): $e',
          );
        }
    }
  }
}
