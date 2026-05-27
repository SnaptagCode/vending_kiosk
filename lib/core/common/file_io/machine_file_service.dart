import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:http/http.dart' as http;
import 'package:vending_kiosk/core/common/cp949/cp949_codec.dart';

enum FileReadStatus { success, directorySuccess, accessError, notFound, empty, readError }

class FileReadResult {
  const FileReadResult._({
    required this.status,
    this.content,
    this.zipBytes,
    this.error,
  });

  final FileReadStatus status;
  final String? content;
  // 디렉토리를 zip으로 묶은 raw bytes → repository에서 file 필드로 전송
  final Uint8List? zipBytes;
  final Object? error;

  // 일반 파일 읽기 성공
  factory FileReadResult.success(String content) => FileReadResult._(status: FileReadStatus.success, content: content);

  // 디렉토리 zip 성공
  factory FileReadResult.successDirectory(Uint8List zipBytes) =>
      FileReadResult._(status: FileReadStatus.directorySuccess, zipBytes: zipBytes);

  factory FileReadResult.accessError(Object error) =>
      FileReadResult._(status: FileReadStatus.accessError, error: error);

  factory FileReadResult.notFound() => FileReadResult._(status: FileReadStatus.notFound);

  factory FileReadResult.empty() => FileReadResult._(status: FileReadStatus.empty);

  factory FileReadResult.readError(Object error) => FileReadResult._(status: FileReadStatus.readError, error: error);
}

class MachineFileService {
  const MachineFileService();

  Future<FileReadResult> readFile(String normalizedPath) async {
    final file = File(normalizedPath);

    // 경로 접근 권한 오류 (exists() 자체가 throw하는 경우)
    bool exists;
    try {
      exists = await file.exists();
    } catch (e) {
      return FileReadResult.accessError(e);
    }

    if (!exists) {
      // 파일로는 없지만 디렉토리일 수 있음 → zip으로 묶어 반환
      if (await Directory(normalizedPath).exists()) {
        return _readDirectory(normalizedPath);
      }
      // 파일도 디렉토리도 아님 → 경로 자체가 없는 경우
      return FileReadResult.notFound();
    }

    // 파일 읽기
    try {
      final bytes = await file.readAsBytes();

      // 파일은 존재하지만 내용이 없는 경우
      if (bytes.isEmpty) return FileReadResult.empty();

      final ext = normalizedPath.split('.').last.toLowerCase();
      const binaryExtensions = {'png', 'jpg', 'jpeg', 'gif', 'bmp', 'pdf', 'zip', 'exe', 'dll'};

      final String content;
      if (binaryExtensions.contains(ext)) {
        // 바이너리 파일 → base64 인코딩
        content = base64Encode(bytes);
      } else {
        content = _decodeText(bytes);
      }

      return FileReadResult.success(content);
    } catch (e) {
      return FileReadResult.readError(e);
    }
  }

  String _decodeText(Uint8List bytes) {
    // UTF-8 BOM (EF BB BF)
    if (bytes.length >= 3 && bytes[0] == 0xEF && bytes[1] == 0xBB && bytes[2] == 0xBF) {
      return utf8.decode(bytes.sublist(3), allowMalformed: true);
    }
    // UTF-16 LE BOM (FF FE)
    if (bytes.length >= 2 && bytes[0] == 0xFF && bytes[1] == 0xFE) {
      final words = <int>[];
      for (var i = 2; i + 1 < bytes.length; i += 2) {
        words.add(bytes[i] | (bytes[i + 1] << 8));
      }
      return String.fromCharCodes(words);
    }
    // UTF-16 BE BOM (FE FF)
    if (bytes.length >= 2 && bytes[0] == 0xFE && bytes[1] == 0xFF) {
      final words = <int>[];
      for (var i = 2; i + 1 < bytes.length; i += 2) {
        words.add((bytes[i] << 8) | bytes[i + 1]);
      }
      return String.fromCharCodes(words);
    }
    // BOM 없음: UTF-8 먼저 시도 (현대 파일의 대부분)
    try {
      return utf8.decode(bytes);
    } catch (_) {}
    // CP949 fallback (한국어 Windows ANSI 레거시 인코딩)
    try {
      return cp949.decode(bytes, allowInvalid: true);
    } catch (_) {}
    // 최후 수단: latin1 (바이트 보존, 한글은 깨질 수 있음)
    return latin1.decode(bytes, allowInvalid: true);
  }

  // 디렉토리를 재귀 탐색하여 zip으로 묶고 raw bytes 반환
  Future<FileReadResult> _readDirectory(String dirPath) async {
    try {
      final archive = Archive();
      final dir = Directory(dirPath);

      // 하위 파일 전체를 상대경로로 archive에 추가 (폴더 구조 유지)
      await for (final entity in dir.list(recursive: true)) {
        if (entity is File) {
          final bytes = await entity.readAsBytes();
          // dirPath 이후 경로만 추출 (예: logs\sub\file.txt)
          final relativePath = entity.path.substring(dirPath.length + 1);
          archive.addFile(ArchiveFile(relativePath, bytes.length, bytes));
        }
      }

      // 디렉토리가 존재하지만 파일이 하나도 없는 경우
      if (archive.isEmpty) return FileReadResult.empty();

      final zipBytes = Uint8List.fromList(ZipEncoder().encode(archive));
      return FileReadResult.successDirectory(zipBytes);
    } catch (e) {
      return FileReadResult.readError(e);
    }
  }

  Future<List<int>> downloadBytesFromUrl(String url) async {
    final response = await http.get(Uri.parse(url));
    if (response.statusCode != 200) {
      throw Exception('URL 다운로드 실패: HTTP ${response.statusCode}');
    }
    return response.bodyBytes;
  }

  // 받아온 경로에 바이트 스트림을 파일로 저장
  // 중간 디렉토리가 없으면 자동 생성
  Future<void> writeFile(String path, List<int> bytes) async {
    final normalizedPath = path.replaceAll('/', r'\');
    final file = File(normalizedPath);
    await file.parent.create(recursive: true);
    await file.writeAsBytes(bytes);
  }
}
