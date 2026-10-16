# Phase 4: TimeTug.Engine package size (findings)

Date: 2026-10-16. Spec: "Compressed size" in `docs/superpowers/specs/2026-10-15-phase-4-engine-c-interface-design.md`. Measured by `dotnet/pack/measure-size.ps1` in the `nuget-pack` job of `timetug-shared`'s `release.yml`, in the dry run [38835208586](https://github.com/binary-companion/timetug-shared/actions/runs/38835208586) (`publish: false`, branch `claude/phase-4-dotnet`, version `0.0.0-dryrun.18`, Swift 6.4 release toolchain on GitHub's `windows-latest` and `windows-11-arm` runners).

## Numbers

The native set holds what `dotnet/pack/assemble-native.ps1` collects: `TimeTugEngineC.dll` plus its Swift runtime closure, walked with `dumpbin /dependents` (CRT, `api-ms-win-*` and System32 DLLs excluded). The zip uses Compress-Archive with Optimal compression, standing in for the MSIX that phase 5 builds.

| Architecture | Files | Uncompressed | Zip (Optimal) |
|---|---:|---:|---:|
| win-x64 | 18 | 74,326,528 bytes (70.9 MB) | 28,223,567 bytes (26.9 MB) |
| win-arm64 | 18 | 72,842,240 bytes (69.5 MB) | 27,569,970 bytes (26.3 MB) |

The package `TimeTug.Engine.0.0.0-dryrun.18.nupkg`, which holds both architectures, the managed wrapper, the header and the fixtures (110 entries), is 55,953,151 bytes (53.4 MB).

The largest files in the win-x64 set:

| File | Bytes |
|---|---:|
| `_FoundationICU.dll` | 38,234,112 |
| `TimeTugEngineC.dll` | 13,310,976 |
| `swiftCore.dll` | 6,064,128 |
| `FoundationEssentials.dll` | 5,712,896 |
| `Foundation.dll` | 4,680,192 |
| `FoundationNetworking.dll` | 1,477,120 |
| `FoundationInternationalization.dll` | 1,473,024 |

Together the other 11 files come to about 3.4 MB. ICU accounts for 51% of the uncompressed set. `FoundationNetworking` and `FoundationXML` are in the closure because `Foundation.dll` links them, not because the engine uses them directly.

## Decision

The spec allows about 60 MB uncompressed per architecture. The measured sets are about 70 MB because the full dependency walk also pulls in `FoundationNetworking` and `FoundationXML`. That figure is not the trigger, though. The trigger is a compressed native payload above 40 MB for one architecture, and both architectures compress to about 27 MB, well under it. So the work to avoid `FoundationInternationalization` (and with it `_FoundationICU.dll`) is not started in phase 4. It stays a recorded option.

The 53 MB package is published on every release, which is within nuget.org's 250 MB limit. The spec's path filter remains a later option, to use only if release frequency makes the volume a problem.

## What would change this

- **A new Swift toolchain grows ICU or Foundation.** `measure-size.ps1` warns in the job summary when a compressed set passes 40 MB, so the job reports it on its own.
- **Phase 5's MSIX compresses worse than Compress-Archive Optimal.** Re-measure against the real installer then.
