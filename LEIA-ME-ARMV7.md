# Black Android, fork armeabi-v7a (32-bit)

Mudancas em relacao ao repo original (RanggaCasper/Black-Android, MIT):

- `app/build.gradle`: `abiFilters "armeabi-v7a"` e NEON ligado.
- `src/d3d/render_thread.cpp`: `vmaxvq_u8` (so existe em arm64) trocado por `AnyBit()`, que funciona nos dois.
- `CMakeLists.txt`: `_FILE_OFFSET_BITS=64` nos builds de 32 bits (ISO maior que 2 GB, offsets de arquivo).
- `UpdateChecker.java`: sem checagem de update por padrao (o repo original so publica APK arm64).
- `.github/workflows/build-armv7.yml`: workflow manual com o SEU xbe; so gera artifact, nao publica release.
- `tools/preparar_xbe.sh`: tira o `default.xbe` da sua ISO e criptografa.

## Antes de tudo: o aparelho precisa ter

- Android 10 ou mais (`minSdk 29`).
- Vulkan 1.1 com `VK_KHR_dynamic_rendering` e timeline semaphore (ver `native/vulkan.cpp`). Teste com o Vulkan Caps Viewer.
  Sem isso o app nao abre.

## Passo a passo

1. Crie um repositorio **privado** no GitHub e suba estes arquivos (sem `assets/`, sem ISO).
2. No Termux: `bash tools/preparar_xbe.sh /sdcard/black.iso`. A ISO tem que ser a versao **USA** do Xbox
   (a Europa so funciona como ISO de jogo no app, o recompilador precisa do xbe USA).
3. Commit de `ci/default.xbe.enc`.
4. GitHub > Settings > Secrets and variables > Actions > New secret: `XBE_KEY` = a senha do passo 2.
5. Actions > Build armv7 > Run workflow. Demora de 30 a 90 minutos ou mais.
6. Baixe o artifact `Black-armv7`, instale o APK e copie o jogo para `/storage/emulated/0/Black`.

## O que ainda nao foi testado

O SDK do motor (TGP482/XboxXBE-Recomp, `runtime/`) nao foi lido. Ele pode ter codigo que assume 64 bits
(mapeamento de memoria do guest com memfd, intrinsics NEON de 64 bits, ponteiros em uint64). Se o build
quebrar, o log do Actions mostra o arquivo; mande o erro.
