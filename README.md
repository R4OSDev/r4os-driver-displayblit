# DISPBLIT.R4D

`DISPBLIT.R4D` is the first external consumer of the canonical R4OS display
present contract. It performs synchronous, bounded XRGB32 multi-region copies
into the kernel-owned boot framebuffer using eight-pixel vector batches and a
scalar tail.

The driver owns no framebuffer mapping, source buffer, fence, or persistent
raster resource. It self-tests separated damage regions and untouched
sentinels before registration. The kernel validates every complete job again
and falls back to its safe CPU copy if the backend is absent, unsupported, or
returns an error.

Build with `Build.bat` on Windows or `./Build.sh` on Linux. The canonical
artifact declaration is `module.R4MF`.

API-Migration 0.90.53: DisplayBlit 0.1.1
Aktueller Einstieg DriverInit2/DriverApi2/Query2:2 mit SDK195/Contract93.
Die technischen API2-Callbacks werden wirklich ueber die neue Tabelle
aufgerufen; eigenstaendige Grafik-/Memory-/Thread-/Resource-Records
behalten ihre eigene Revision1. Alte DriverApi-Versionszahlen in den
folgenden historischen Abschnitten beschreiben den damaligen Stand.
Pflichtfaehigkeiten und optionale passive/software Modi bleiben getrennt.
Shared DriverPollBudget begrenzt die AMD4096-Versuche und NVIDIA8-Schritt-
Callbacks zusaetzlich zu ihren urspruenglichen Zeitgrenzen. Ablauf bestaetigt
weder Work noch DMA, Mapping, GPU-Fence oder Unload. Bestehende Original-
Ownerorakel bleiben erhalten. Konkrete Host-/Windowskompilat-/native
Modellbelege und physische Grenzen: Docs/API/ConsumerMigration.txt und
Research/API-ABI/Migration/0.90.53/Abnahme.json. AMD/NVIDIA-Hardware und
bekannte NVIDIA-Hang-/Shutdownbefunde werden dadurch nicht abgenommen.
