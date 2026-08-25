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
