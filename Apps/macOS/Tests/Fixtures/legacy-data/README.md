# legacy-data

A synthetic Mac data directory as the last Swift release (timetug-shared 1.8.6, calendar-connectors 1.2.2) left it.
Every file is a byte copy of a library fixture; nothing here comes from a real container. The file names are the ones
the 1.x engine uses (`AppSupportFiles.names`). Used by `UpgradeFromSwiftEngineTests`.

| File | Source fixture |
|---|---|
| `accounts.json` | calendar-connectors `fixtures/persisted-formats/1.0.7/connections.json` (one account each of google, microsoft, icloud, caldav, icalsub) |
| `sync-state.json` | calendar-connectors `fixtures/persisted-formats/1.0.7/sync-state.json` |
| `takeover-ledger.json` | timetug-shared `fixtures/engine/takeover-ledger.json` (4 keys) |
| `dedup-state.json` | timetug-shared `fixtures/engine/dedup-state.json` (1 lesson, 1 verdict) |
| `userdefaults-takeoverSettings.v1.json` | timetug-shared `fixtures/engine/settings-legacy.json`; the 1.x Mac app kept this JSON in UserDefaults under `takeoverSettings.v1`, not in the data directory, so the test loads it into a suite rather than copying it |

Apple Calendar (EventKit) has no file: it is the system calendar and is switched off in the test.
