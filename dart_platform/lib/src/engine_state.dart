enum EngineMode { external, embedded }

enum EngineStatus { idle, downloadingEngine, downloadingModel, starting, ready, error }

class EngineState {
  EngineState({
    this.mode = EngineMode.embedded,
    this.status = EngineStatus.idle,
    this.statusMessage,
    this.activeModelPath,
    this.serverPort,
    this.contextSize = 4096,
  });

  EngineMode mode;
  EngineStatus status;
  String? statusMessage;
  String? activeModelPath;
  int? serverPort;
  int contextSize;

  Map<String, dynamic> toJson() => {
        'mode': mode.name,
        'status': status.name,
        'statusMessage': statusMessage,
        'activeModelPath': activeModelPath,
        'serverPort': serverPort,
        'contextSize': contextSize,
      };
}
