#!/bin/sh
# A card image with the data partition already in it: games, saves, settings and themes from a copy of a BANANA
# drive, so a new card comes out of the writer ready, with nothing to copy after the first boot.
#
#   tools/make-full-image.sh <banana-*.img[.gz]> <card size in bytes> <folder> [out.img]
#
# <card size>: the exact size of the card it will be written to (Windows: Get-Disk, the Size column; Linux:
# lsblk -b). The data partition ends there, as the first boot would make it: exFAT can't grow afterwards, and a
# partition past the card's end would lose what is written there. <folder>: what goes on the BANANA drive (roms/,
# bios/, saves/, states/, banana/, drastic/, superdrastic/...), copied as it is.
#
# The partition is made as the first boot makes it (the fourth, after the root slots, to the card's end; exFAT
# labelled BANANA) and named banana-data, so rcS mounts it and the first boot leaves it alone. The image ends after
# the partition's last used cluster: a writer writes the system and the files, not the empty rest of the card (an
# exFAT's free clusters can hold anything, and nothing of it lives at its end). The GPT's backup copy, at the card's
# end, isn't in it: Linux and Windows read the primary one.
# Needs sfdisk, losetup, mkfs.exfat (exfatprogs), python3 and root (or sudo); the kernel's exFAT, or exfat-fuse.
set -e
IMG=$1; CARD=$2; SRC=$3
[ -f "$IMG" ] && [ -d "$SRC" ] && [ "$CARD" -gt 0 ] 2>/dev/null ||
    { echo "usage: $0 <banana-*.img[.gz]> <card size in bytes> <folder> [out.img]" >&2; exit 2; }
OUT=${4:-$(basename "${IMG%.gz}" .img)-full.img}
SUDO=; [ "$(id -u)" = 0 ] || SUDO=sudo
PATH=$PATH:/sbin:/usr/sbin

echo "image: $IMG -> $OUT"
case $IMG in *.gz) gunzip -c "$IMG" > "$OUT" ;; *) cp "$IMG" "$OUT" ;; esac
[ "$CARD" -gt $(($(stat -c %s "$OUT") + 64 * 1024 * 1024)) ] || { echo "the card is smaller than the system" >&2; exit 1; }
# the card's size (sparse: nothing written yet), the GPT's backup at its end, and the partition over the rest
truncate -s "$CARD" "$OUT"
sfdisk -q --relocate gpt-bak-std "$OUT"
echo 'type=EBD0A0A2-B9E5-4433-87C0-68B6B72699C7, name="banana-data"' |
    sfdisk -q --no-reread --no-tell-kernel --append --wipe-partitions always "$OUT"
part() { sfdisk -J "$OUT" | python3 -c "import json,sys; p=json.load(sys.stdin)['partitiontable']['partitions']; print(p[3]['$1']*512)"; }
AT=$(part start); SIZE=$(part size)
NEED=$(du -sb "$SRC" | cut -f1)
[ "$NEED" -lt $((SIZE - SIZE / 50)) ] || { echo "the folder ($NEED bytes) doesn't fit in the data partition ($SIZE)" >&2; exit 1; }
echo "data partition: $SIZE bytes at $AT; copying $NEED bytes"

MNT=$(mktemp -d); LOOP=
done_() {
    mountpoint -q "$MNT" && $SUDO umount "$MNT"
    [ -n "$LOOP" ] && $SUDO losetup -d "$LOOP"
    rmdir "$MNT"
}
trap 'rc=$?; done_; exit $rc' EXIT
LOOP=$($SUDO losetup --find --show --offset "$AT" --sizelimit "$SIZE" "$OUT")
$SUDO mkfs.exfat -L BANANA "$LOOP" >/dev/null
$SUDO mount -t exfat -o uid=$(id -u),gid=$(id -g),iocharset=utf8 "$LOOP" "$MNT" 2>/dev/null ||
    $SUDO mount.exfat-fuse -o allow_other,uid=$(id -u),gid=$(id -g) "$LOOP" "$MNT"
# (exFAT keeps no owners or permissions: the files and their times; Windows' own folders stay behind)
(cd "$SRC" && find . -mindepth 1 -maxdepth 1 ! -name 'System Volume Information' ! -name '$RECYCLE.BIN' \
    -exec cp -R --preserve=timestamps -t "$MNT" {} +)
sync
$SUDO umount "$MNT"
$SUDO losetup -d "$LOOP"; LOOP=

# the end of the partition's last used cluster, from the exFAT's allocation bitmap
END=$(python3 - "$OUT" "$AT" <<'EOF'
import struct, sys
f = open(sys.argv[1], 'rb'); at = int(sys.argv[2])
def read(off, n): f.seek(at + off); return f.read(n)
b = read(0, 512)
assert b[3:11] == b'EXFAT   ', 'not exFAT'
fat, heap, count, root = struct.unpack_from('<I4xIII', b, 80)
sector = 1 << b[108]; cluster = sector << b[109]
fat *= sector; heap *= sector
def chain(c):
    while 2 <= c < count + 2:
        yield heap + (c - 2) * cluster
        c = struct.unpack('<I', read(fat + 4 * c, 4))[0]
bitmap = None
for off in chain(root):
    d = read(off, cluster)
    for i in range(0, cluster, 32):
        if d[i] == 0x81: bitmap = struct.unpack_from('<IQ', d, i + 20)
        if d[i] == 0: break
    if bitmap or d[i] == 0: break
assert bitmap, 'no allocation bitmap'
data = b''.join(read(off, cluster) for off in chain(bitmap[0]))[:bitmap[1]]
last = len(data.rstrip(b'\0')) - 1
used = last * 8 + data[last].bit_length() if last >= 0 else 0
print(at + heap + used * cluster)
EOF
)
# rounded up to a MiB, never past the card
END=$(( (END + 1048575) / 1048576 * 1048576 )); [ "$END" -le "$CARD" ] || END=$CARD
truncate -s "$END" "$OUT"
echo "done: $OUT ($END bytes). Write it to the card (Raspberry Pi Imager: Use custom image); gzip it to carry it."
