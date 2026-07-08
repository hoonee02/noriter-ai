import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

/// Manages the llama-server.exe lifecycle: download, install, start/stop.
class LlamaEngineManager {
  LlamaEngineManager();

  Process? _serverProcess;
  int? _activePort;
  String? _activeModelPath;

  String get _appDataDir {
    return Platform.environment['APPDATA'] ??
        p.join(
          Platform.environment['USERPROFILE'] ?? '',
          'AppData',
          'Roaming',
        );
  }

  String get engineDir => p.join(_appDataDir, 'noriter-ai', 'engine');
  String get modelsDir => p.join(_appDataDir, 'noriter-ai', 'models');
  String get serverExePath =>
      _findServerExecutablePath() ?? p.join(engineDir, 'llama-server.exe');

  bool get isInstalled => _findServerExecutablePath() != null;
  int? get activePort => _activePort;
  String? get activeModelPath => _activeModelPath;

  /// Downloads llama.cpp Windows x64 CPU build from GitHub releases, extracts
  /// llama-server.exe and all DLLs to [engineDir].
  Future<void> downloadEngine({void Function(String status)? onStatus}) async {
    onStatus?.call('GitHub 최신 릴리스 정보 조회 중...');

    final response = await http.get(
      Uri.parse(
          'https://api.github.com/repos/ggerganov/llama.cpp/releases/latest'),
      headers: {'User-Agent': 'noriter-ai/1.0'},
    );

    if (response.statusCode != 200) {
      throw Exception('GitHub API 조회 실패: HTTP ${response.statusCode}');
    }

    final release = jsonDecode(response.body) as Map<String, dynamic>;
    final assets = release['assets'] as List<dynamic>;

    Map<String, dynamic>? targetAsset;
    for (final asset in assets) {
      final name = (asset['name'] as String).toLowerCase();
      if (name.contains('bin-win') &&
          name.contains('x64') &&
          !name.contains('cuda') &&
          !name.contains('vulkan') &&
          !name.contains('sycl') &&
          !name.contains('kompute') &&
          name.endsWith('.zip')) {
        targetAsset = asset as Map<String, dynamic>;
        break;
      }
    }

    if (targetAsset == null) {
      throw Exception(
          '호환 가능한 Windows x64 CPU 빌드 에셋을 찾지 못했습니다.\n'
          '수동으로 https://github.com/ggerganov/llama.cpp/releases/latest 에서 '
          'bin-win-x64.zip 을 다운로드해 ${engineDir} 에 llama-server.exe 를 넣어주세요.');
    }

    final downloadUrl = targetAsset['browser_download_url'] as String;
    final assetName = targetAsset['name'] as String;

    await Directory(engineDir).create(recursive: true);
    await Directory(modelsDir).create(recursive: true);

    final zipPath = p.join(engineDir, assetName);
    onStatus?.call('다운로드 중: $assetName');
    await _downloadFile(downloadUrl, zipPath, onStatus: onStatus);

    onStatus?.call('압축 해제 중...');
    await _extractZip(zipPath, engineDir, onStatus: onStatus);

    try {
      await File(zipPath).delete();
    } catch (_) {}

    if (!isInstalled) {
      throw Exception(
          'llama-server.exe 추출에 실패했습니다. 수동 설치를 시도하세요.');
    }
    onStatus?.call('엔진 설치 완료!');
  }

  Future<void> _downloadFile(
    String url,
    String savePath, {
    void Function(String status)? onStatus,
  }) async {
    final client = http.Client();
    try {
      final request = http.Request('GET', Uri.parse(url));
      final streamed = await client.send(request);
      final total = streamed.contentLength ?? 0;
      final file = File(savePath);
      final sink = file.openWrite();
      int received = 0;
      int lastReportedPercent = -1;

      await for (final chunk in streamed.stream) {
        sink.add(chunk);
        received += chunk.length;
        if (total > 0) {
          final percent = received * 100 ~/ total;
          if (percent != lastReportedPercent && percent % 5 == 0) {
            lastReportedPercent = percent;
            final mb = (received / 1024 / 1024).toStringAsFixed(1);
            final totalMb = (total / 1024 / 1024).toStringAsFixed(1);
            onStatus?.call('다운로드 중... $mb MB / $totalMb MB ($percent%)');
          }
        }
      }
      await sink.flush();
      await sink.close();
    } finally {
      client.close();
    }
  }

  Future<void> _extractZip(
    String zipPath,
    String destDir, {
    void Function(String status)? onStatus,
  }) async {
    // Primary: PowerShell Expand-Archive (reliable for large files)
    final psCmd =
        "Expand-Archive -Path '$zipPath' -DestinationPath '$destDir' -Force";
    final result = await Process.run(
      'powershell',
      ['-NoProfile', '-NonInteractive', '-Command', psCmd],
    );

    if (result.exitCode == 0) {
      _flattenExtractedFiles(destDir);
      return;
    }

    // Fallback: archive package
    onStatus?.call('archive 패키지로 압축 해제 중 (fallback)...');
    try {
      final bytes = await File(zipPath).readAsBytes();
      final archive = ZipDecoder().decodeBytes(bytes);
      for (final file in archive) {
        final name = p.basename(file.name);
        if ((name.endsWith('.exe') || name.endsWith('.dll')) &&
            file.isFile) {
          final outPath = p.join(destDir, name);
          File(outPath).writeAsBytesSync(file.content as List<int>);
        }
      }
    } catch (e) {
      throw Exception('ZIP 압축 해제 실패: $e\nPowerShell 오류: ${result.stderr}');
    }
  }

  /// Flattens subdirectory structure: copies .exe/.dll files to the top-level
  /// destDir. llama.cpp ZIPs typically extract into a single subdirectory.
  void _flattenExtractedFiles(String destDir) {
    final dir = Directory(destDir);
    final topNorm = p.normalize(destDir);
    for (final entity in dir.listSync(recursive: true)) {
      if (entity is File) {
        final name = p.basename(entity.path);
        if ((name.endsWith('.exe') || name.endsWith('.dll')) &&
            p.normalize(entity.parent.path) != topNorm) {
          final dest = p.join(destDir, name);
          if (!File(dest).existsSync()) {
            try {
              entity.copySync(dest);
            } catch (_) {}
          }
        }
      }
    }
  }

  /// Starts llama-server.exe with the given model. Polls /health until ready
  /// (timeout: 30s).
  Future<Process> startServer(String modelPath, {int port = 8080}) async {
    final resolvedExe = _findServerExecutablePath();
    if (resolvedExe == null) {
      throw Exception(
          'llama-server executable not found in: $engineDir\n'
          'Please click [Download Engine] first.');
    }
    await stopServer();

    _activePort = port;
    _activeModelPath = modelPath;

    final process = await Process.start(
      resolvedExe,
      ['-m', modelPath, '--port', '$port', '--host', '127.0.0.1', '-c', '4096', '-ngl', '0'],
      workingDirectory: File(resolvedExe).parent.path,
    );
    _serverProcess = process;

    process.stdout
        .transform(const Utf8Decoder(allowMalformed: true))
        .listen((s) => stdout.write('[llama-server] $s'));
    process.stderr
        .transform(const Utf8Decoder(allowMalformed: true))
        .listen((s) => stderr.write('[llama-server] $s'));

    final deadline = DateTime.now().add(const Duration(seconds: 60));
    while (DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 500));
      try {
        final resp = await http
            .get(Uri.parse('http://127.0.0.1:$port/health'))
            .timeout(const Duration(seconds: 2));
        if (resp.statusCode == 200) return process;
      } catch (_) {}
    }

    throw Exception('llama-server가 60초 내에 응답하지 않았습니다.');
  }

  Future<void> stopServer() async {
    if (_serverProcess != null) {
      try {
        _serverProcess!.kill();
      } catch (_) {}
      _serverProcess = null;
    }
    _activePort = null;
    _activeModelPath = null;
  }

  /// Lists .gguf files in [modelsDir].
  List<String> listLocalModels() {
    final dir = Directory(modelsDir);
    if (!dir.existsSync()) return [];
    return dir
        .listSync()
        .whereType<File>()
        .where((f) => f.path.toLowerCase().endsWith('.gguf'))
        .map((f) => f.path)
        .toList()
      ..sort();
  }

  String? _findServerExecutablePath() {
    final engine = Directory(engineDir);
    if (!engine.existsSync()) return null;

    String? fallback;
    for (final entity in engine.listSync(recursive: true)) {
      if (entity is! File) continue;
      final name = p.basename(entity.path).toLowerCase();
      if (!name.endsWith('.exe')) continue;
      if (!name.startsWith('llama-server')) continue;
      if (name == 'llama-server.exe') {
        return entity.path;
      }
      fallback ??= entity.path;
    }
    return fallback;
  }
}
