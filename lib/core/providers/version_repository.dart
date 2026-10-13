import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';

class VersionRepository {
  final String githubRepo = "SnaptagCode/vending_kiosk";

  Future<String> getCurrentVersion() async {
    try {
      // pubspec.yaml의 버전을 가져옵니다
      final packageInfo = await PackageInfo.fromPlatform();
      final version = packageInfo.version;
      // 버전에 'v' 접두사가 없으면 추가
      return version.startsWith('v') ? version : 'v$version';
    } catch (e) {
      // 오류 발생 시 .env.version 파일에서 읽기 시도
      return 'v0.0.0';
    }
  }

  Future<String> getLatestVersionFromGitHub() async {
    final response = await http.get(
      Uri.parse('https://api.github.com/repos/$githubRepo/releases/latest'),
    );

    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      final rawVersion = data['tag_name'];
      return rawVersion;
    } else {
      throw Exception('Failed to load latest version');
    }
  }
}
