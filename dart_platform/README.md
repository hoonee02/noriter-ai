# Noriter AI Dart Platform (Windows-ready)

This folder contains a standalone Dart application scaffold intended for
running on Windows without code signing.

## Features implemented

- Standalone Dart app entrypoint (`bin/noriter_ai.dart`)
- OpenAI-compatible model provider abstraction
- `/models` command to list available models from configured endpoint
- Persistent cumulative work log appender to:
  - `.noriter-ai/project-plan-log.md`

## Requirements

- Dart SDK 3.3+

## Run (development)

```bash
cd dart_platform
dart pub get
dart run bin/noriter_ai.dart
```

Optional environment variables:

- `NORITER_MODEL_ENDPOINT` (default `http://localhost:1234/v1`)
- `NORITER_MODEL_API_KEY` (default `local`)
- `NORITER_MODEL_NAME` (default `local-model`)

## Build unsigned Windows executable

```bash
cd dart_platform
dart compile exe bin/noriter_ai.dart -o build\noriter-ai.exe
```

The generated EXE can run without code signing, but Windows SmartScreen
warnings may appear.
