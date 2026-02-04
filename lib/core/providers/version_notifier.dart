import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_snaptag_kiosk/core/providers/version_repository.dart';

final versionRepositoryProvider = Provider((ref) => VersionRepository());

final versionStateProvider = StateNotifierProvider<VersionNotifier, VersionState>(
  (ref) => VersionNotifier(ref.read(versionRepositoryProvider)),
);

class VersionNotifier extends StateNotifier<VersionState> {
  final VersionRepository _repo;

  VersionNotifier(this._repo)
      : super(VersionState(currentVersion: 'v2.4.9', latestVersion: 'v2.4.9', isLoading: true)) {
    loadVersions();
  }

  Future<void> loadVersions() async {
    try {
      final current = await _repo.getCurrentVersion();
      final latest = await _repo.getLatestVersionFromGitHub();
      state = state.copyWith(
        currentVersion: current,
        latestVersion: latest,
        isLoading: false,
      );
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }
}

class VersionState {
  final String currentVersion;
  final String latestVersion;
  final bool isLoading;
  final String? error;

  VersionState({
    this.currentVersion = "v2.4.9",
    this.latestVersion = "v2.4.9",
    this.isLoading = false,
    this.error,
  });

  VersionState copyWith({
    String? currentVersion,
    String? latestVersion,
    bool? isLoading,
    String? error,
  }) {
    return VersionState(
      currentVersion: currentVersion ?? this.currentVersion,
      latestVersion: latestVersion ?? this.latestVersion,
      isLoading: isLoading ?? this.isLoading,
      error: error,
    );
  }
}
