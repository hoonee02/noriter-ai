import { compileStreaming } from './worker.dart.mjs';

async function main() {
  const compiled = await compileStreaming(fetch('worker.dart.wasm'));
  const instantiated = await compiled.instantiate({});
  await instantiated.invokeMain();
}

main().catch((e) => console.error('worker wasm boot failed:', e));
