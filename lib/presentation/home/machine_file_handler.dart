import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vending_kiosk/core/common/logger/slack_log_service.dart';
import 'package:vending_kiosk/core/common/file_io/machine_file_service.dart';
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
                step: 'ERROR',
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
                step: 'ERROR',
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
              step: 'ERROR',
            );
      case FileReadStatus.readError:
        try {
          await _ref.read(kioskRepositoryProvider).sendKioskLog(
                KioskLogRequest.withLogId(
                    logId: logId, machineId: machineId, title: fileName, content: '파일 읽기 실패: ${result.error}'),
                step: 'ERROR',
              );
        } catch (_) {
          SlackLogService().sendErrorLogToSlack(
            '*[MachineId: $machineId / LogId: $logId]* 파일 읽기 실패 알림 전송 실패 ($path): ${result.error}',
          );
        }
      case FileReadStatus.success:
        try {
          await _ref.read(kioskRepositoryProvider).sendKioskLog(
                KioskLogRequest.withLogId(
                    logId: logId, machineId: machineId, title: fileName, content: result.content!),
              );
        } catch (e) {
          SlackLogService().sendErrorLogToSlack(
            '*[MachineId: $machineId / LogId: $logId]* 로그 전송 실패 ($path): $e',
          );
        }
      case FileReadStatus.directorySuccess:
        try {
          await _ref.read(kioskRepositoryProvider).sendKioskLog(
                KioskLogRequest.withLogId(
                    logId: logId, machineId: machineId, title: '$fileName.zip', content: ''),
                zipFile: result.zipBytes,
              );
        } catch (e) {
          SlackLogService().sendErrorLogToSlack(
            '*[MachineId: $machineId / LogId: $logId]* 디렉토리 zip 전송 실패 ($path): $e',
          );
        }
    }
  }

  Future<void> downloadFiles(List<MachineDownloadItem> items, int machineId) async {
    for (final item in items) {
      final bytes = base64Decode(item.content);
      await downloadFile(item.path, bytes, item.id, machineId);
    }
  }

  Future<void> downloadLogFiles(List<MachineLogItem> items, int machineId) async {
    for (final item in items) {
      if (item.urlPath == null) continue;
      await downloadFileFromUrl(item.urlPath!, item.path, item.id, machineId);
    }
  }

  Future<void> downloadFileFromUrl(String urlPath, String path, int logId, int machineId) async {
    final normalizedPath = path.replaceAll('/', r'\');
    final fileName = normalizedPath.split(r'\').last;

    try {
      final bytes = await _fileService.downloadBytesFromUrl(urlPath);
      await _fileService.writeFile(path, bytes);

      try {
        await _ref.read(kioskRepositoryProvider).sendKioskLog(
              KioskLogRequest.withLogId(
                  logId: logId, machineId: machineId, title: fileName, content: '파일 저장 완료: $path'),
            );
      } catch (e) {
        SlackLogService().sendErrorLogToSlack(
          '*[MachineId: $machineId / LogId: $logId]* 파일 저장 완료 알림 전송 실패 ($path): $e',
        );
      }
    } catch (e) {
      try {
        await _ref.read(kioskRepositoryProvider).sendKioskLog(
              KioskLogRequest.withLogId(
                  logId: logId, machineId: machineId, title: fileName, content: '파일 저장 실패: $e'),
              step: 'ERROR',
            );
      } catch (_) {
        SlackLogService().sendErrorLogToSlack(
          '*[MachineId: $machineId / LogId: $logId]* 파일 저장 실패 알림 전송 실패 ($path): $e',
        );
      }
    }
  }

  Future<void> downloadFile(String path, List<int> bytes, int logId, int machineId) async {
    final normalizedPath = path.replaceAll('/', r'\');
    final fileName = normalizedPath.split(r'\').last;

    try {
      await _fileService.writeFile(path, bytes);

      // 저장 성공 → 서버에 알림
      try {
        await _ref.read(kioskRepositoryProvider).sendKioskLog(
              KioskLogRequest.withLogId(
                  logId: logId, machineId: machineId, title: fileName, content: '파일 저장 완료: $path'),
            );
      } catch (e) {
        SlackLogService().sendErrorLogToSlack(
          '*[MachineId: $machineId / LogId: $logId]* 파일 저장 완료 알림 전송 실패 ($path): $e',
        );
      }
    } catch (e) {
      // 저장 실패 → 서버에 알림
      try {
        await _ref.read(kioskRepositoryProvider).sendKioskLog(
              KioskLogRequest.withLogId(
                  logId: logId, machineId: machineId, title: fileName, content: '파일 저장 실패: $e'),
              step: 'ERROR',
            );
      } catch (_) {
        SlackLogService().sendErrorLogToSlack(
          '*[MachineId: $machineId / LogId: $logId]* 파일 저장 실패 알림 전송 실패 ($path): $e',
        );
      }
    }
  }
}
