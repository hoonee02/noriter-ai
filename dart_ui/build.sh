#!/usr/bin/env bash
# Compiles the UI (lib/main.dart) and the Web Worker business-logic module
# (lib/worker_main.dart) to separate WasmGC modules, and assembles
# build/web (Tauri's frontendDist). Two modules because a worker has no DOM
# access and the main thread has no business calling into a worker's
# module directly -- they only talk over postMessage.
set -euo pipefail
cd "$(dirname "$0")"

dart pub get
mkdir -p build/web
dart compile wasm lib/main.dart -o build/web/main.dart.wasm
dart compile wasm lib/worker_main.dart -o build/web/worker.dart.wasm

cp web/index.html build/web/index.html
cp web/style.css build/web/style.css
cp web/bootstrap.js build/web/bootstrap.js
cp web/worker_bootstrap.js build/web/worker_bootstrap.js
