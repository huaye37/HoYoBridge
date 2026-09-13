# Genshin compatibility shim

`gptk4_msaa_version.c` is MacGameBridge-owned source for the native Windows
`version.dll` proxy bundled in the development app. It forwards all VERSION APIs to the Wine
builtin module renamed to `versi0n.dll` during runtime preparation and provides two independent,
environment-gated features:

- `MGB_GPTK_MSAA_SHIM=1` works around the GPTK 4.0 beta 2 crash in
  `ID3D11Device::CheckMultisampleQualityLevels`.
- `MGB_FPS_LIMIT=120` or `144` scans the loaded game's `il2cpp` section for the current frame-rate
  target, requires a single writable target, and then keeps that target at the requested value.

The FPS target-resolution approach is derived from the MIT-licensed
[`34736384/genshin-fps-unlock`](https://github.com/34736384/genshin-fps-unlock). MacGameBridge's
implementation adds image-bound checks, writable-page validation and unique-target fail-closed
behavior. See `LICENSES/genshin-fps-unlock-MIT.txt`.

The workaround reports one quality level for sample count 1 and zero for multisampled counts.
All other D3D11 device methods continue to use GPTK/D3DMetal. This intentionally disables MSAA
exposure until the upstream COM call is safe.

Maintainer build command (pinned llvm-mingw toolchain):

```bash
LocalRuntimes/Tools/llvm-mingw-20260616/bin/x86_64-w64-mingw32-gcc \
  -O2 -fno-builtin -shared -nostdlib -Wl,--entry,DllMain \
  -Wno-dll-attribute-on-redeclaration \
  RuntimeAssets/GPTKCompatibility/gptk4_msaa_version.c \
  -lkernel32 \
  -o RuntimeAssets/GPTKCompatibility/gptk4-msaa-version.dll
```

The app build verifies the checked-in DLL size and SHA-256 before copying it into the app bundle.
