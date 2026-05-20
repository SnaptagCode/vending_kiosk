import 'dart:convert';
import 'dart:io';

import 'package:vending_kiosk/core/common/cp949/cp949_codec.dart';

enum FileReadStatus { success, accessError, notFound, empty, readError }

class FileReadResult {
  const FileReadResult._({
    required this.status,
    this.content,
    this.error,
  });

  final FileReadStatus status;
  final String? content;
  final Object? error;

  factory FileReadResult.success(String content) =>
      FileReadResult._(status: FileReadStatus.success, content: content);

  factory FileReadResult.accessError(Object error) =>
      FileReadResult._(status: FileReadStatus.accessError, error: error);

  factory FileReadResult.notFound() =>
      FileReadResult._(status: FileReadStatus.notFound);

  factory FileReadResult.empty() =>
      FileReadResult._(status: FileReadStatus.empty);

  factory FileReadResult.readError(Object error) =>
      FileReadResult._(status: FileReadStatus.readError, error: error);
}

class MachineFileService {
  const MachineFileService();

  Future<FileReadResult> readFile(String normalizedPath) async {
    final file = File(normalizedPath);

    bool exists;
    try {
      exists = await file.exists();
    } catch (e) {
      return FileReadResult.accessError(e);
    }

    if (!exists) return FileReadResult.notFound();

    try {
      final bytes = await file.readAsBytes();

      if (bytes.isEmpty) return FileReadResult.empty();

      final ext = normalizedPath.split('.').last.toLowerCase();
      const binaryExtensions = {'png', 'jpg', 'jpeg', 'gif', 'bmp', 'pdf', 'zip', 'exe', 'dll'};

      final String content;
      if (binaryExtensions.contains(ext)) {
        content = base64Encode(bytes);
      } else {
        String decoded;
        try {
          decoded = cp949.decode(bytes, allowInvalid: true);
        } catch (_) {
          decoded = latin1.decode(bytes);
        }
        content = decoded;
      }

      return FileReadResult.success(content);
    } catch (e) {
      return FileReadResult.readError(e);
    }
  }

  // TODO: 파일 쓰기
  Future<void> writeFile(String path, String content) async {}

  // TODO: 파일 수정
  Future<void> modifyFile(String path, String content) async {}

  // TODO: 파일 삭제
  Future<void> deleteFile(String path) async {}
}
