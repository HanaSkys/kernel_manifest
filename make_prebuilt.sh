#!/bin/bash
# Build a device_xiaomi_duchamp-kernel style prebuilt tree from a kleaf build.
# Based on rio004's copy_kernel.sh, but takes the module lists from the device
# tree (the lists crDroid actually loads) and never touches the source trees.
#
# Usage: make_prebuilt.sh <kernel_src> <device_tree> <reference_prebuilt> <out_dir>
#   kernel_src          ~/duchamp-kernel-src
#   device_tree         ~/crDroid/device/xiaomi/duchamp
#   reference_prebuilt  ~/crDroid/device/xiaomi/duchamp-kernel (dtbo.img + list files)
#   out_dir             new, empty directory to fill
 
set -euo pipefail
 
KSRC=$(readlink -f "${1:?kernel_src}")
DT=$(readlink -f "${2:?device_tree}")
REF=$(readlink -f "${3:?reference_prebuilt}")
OUT=${4:?out_dir}
 
DIST="$KSRC/out/dist"
STRIP="$KSRC/prebuilts/clang/host/linux-x86/clang-r487747c/bin/llvm-strip"
SOC=mt6897
LISTS="system_dlkm.modules.load vendor_dlkm.modules.load vendor_ramdisk.modules.load vendor_ramdisk.modules.load.recovery"
EXTRA_MODULES="gps_drv_dl_v051.ko gps_pwr.ko gps_scp.ko"
 
[ -d "$DIST" ] || { echo "No existe $DIST"; exit 1; }
[ -x "$STRIP" ] || { echo "No existe $STRIP"; exit 1; }
if [ -e "$OUT" ] && [ -n "$(ls -A "$OUT")" ]; then
    echo "$OUT no está vacío; usa una carpeta nueva"; exit 1
fi
mkdir -p "$OUT/modules" "$OUT/dtb"
OUT=$(readlink -f "$OUT")
 
missing=0
find_one() {
    # Prefer the stripped install tree copy when several exist.
    find -L "$DIST" -type f -name "$1" -print -quit
}
 
copy_artifact() { # name dest
    local f; f=$(find_one "$1")
    if [ -z "$f" ]; then echo "FALTA: $1"; missing=1; return; fi
    cp "$f" "$2"; chmod 0644 "$2/$(basename "$f")"
}
 
# Modules: every entry of the device tree lists, plus extras.
mods=$(for l in $LISTS; do
           [ -f "$DT/$l" ] || { echo "FALTA LISTA: $DT/$l" >&2; exit 1; }
           grep -v '^\s*#' "$DT/$l" | sed 's/\s*$//' | grep -v '^$'
       done; printf '%s\n' $EXTRA_MODULES)
for m in $(printf '%s\n' "$mods" | sort -u); do
    copy_artifact "$m" "$OUT/modules"
done
"$STRIP" --strip-debug "$OUT"/modules/*.ko
 
# The prebuilt repo keeps its own copy of the lists; carry them over unchanged.
for l in $LISTS; do
    [ -f "$REF/modules/$l" ] && cp "$REF/modules/$l" "$OUT/modules/"
done
 
copy_artifact Image.lz4 "$OUT"
copy_artifact kernel-uapi-headers.tar.gz "$OUT"
copy_artifact "$SOC.dtb" "$OUT/dtb"
 
# dtbo.img is not produced by the kleaf dist (duchamp.dts is not in the dtb
# Makefile); reuse the reference one until we build it ourselves.
cp "$REF/dtbo.img" "$OUT/"
 
[ "$missing" = 0 ] || { echo "Hay archivos faltantes, revisa arriba"; exit 1; }
echo "Listo: $(ls "$OUT"/modules/*.ko | wc -l) módulos en $OUT"
 
