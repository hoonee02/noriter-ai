import { compileStreaming } from './main.dart.mjs';

async function main() {
  const compiled = await compileStreaming(fetch('main.dart.wasm'));
  const instantiated = await compiled.instantiate({});
  await instantiated.invokeMain();
}

main().catch((e) => console.error('dart wasm boot failed:', e));
