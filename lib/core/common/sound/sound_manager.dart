import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:vending_kiosk/core/common/constants/image_paths.dart';
import 'package:flutter_soloud/flutter_soloud.dart';

class SoundManager {
  static final SoundManager _instance = SoundManager._internal();
  factory SoundManager() => _instance;

  final SoLoud _soloud = SoLoud.instance;
  AudioSource? _soundSource; // 🔹 로드된 사운드를 저장

  SoundManager._internal();

  /// 🔹 SoLoud 초기화 및 사운드 미리 로드
  Future<void> init() async {
    // SoLoud가 임시 파일을 저장할 캐시 디렉토리를 미리 생성 (macOS 샌드박스 환경 대응)
    if (Platform.isMacOS) {
      final cacheDir = await getApplicationCacheDirectory();
      await cacheDir.create(recursive: true);
    }
    await _soloud.init();
    _soundSource ??= await _soloud.loadAsset(SnaptagSounds.beep); // ✅ 한 번만 로드
  }

  /// 🔹 사운드 재생 (기존에 로드된 파일을 재사용)
  Future<void> playSound() async {
    if (_soundSource == null) {
      await init(); // ✅ 사운드가 로드되지 않았다면 초기화
    }
    await _soloud.play(_soundSource!);
  }

  /// 🔹 SoLoud 해제
  Future<void> dispose() async {
    _soloud.deinit();
    _soundSource = null;
  }
}
