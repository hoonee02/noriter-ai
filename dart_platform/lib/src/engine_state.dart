enum EngineMode { external, embedded }

enum EngineStatus { idle, downloadingEngine, downloadingModel, starting, ready, error }

class EngineState {
  EngineState({
    this.mode = EngineMode.embedded,
    this.status = EngineStatus.idle,
    this.statusMessage,
    this.activeModelPath,
    this.serverPort,
  });

  EngineMode mode;
  EngineStatus status;
  String? statusMessage;
  String? activeModelPath;
  int? serverPort;

  Map<String, dynamic> toJson() => {
        'mode': mode.name,
        'status': status.name,
        'statusMessage': statusMessage,
        'activeModelPath': activeModelPath,
        'serverPort': serverPort,
      };
}
