#!/bin/sh
# A BananaMiku release on GitHub, in the shape Settings > System > Update looks for (system/rootfs/usr/libexec/banana/
# update, "check"): each handheld's banana-<board>-<VERSION>.update.tar and a SHA256SUMS-<board>.txt listing it, on a
# release tagged v<VERSION> in March93B/BananaMiku. A handheld on a lower version is offered it.
#
#   tools/release.sh [--notes <file>] [--prerelease] [--image] [board...]     (boards: rgds-plus by default)
#
# Build first (make rgds-plus) with VERSION raised: the handheld compares the package's version number by number
# (0.5.3.6.1 > 0.5.3.6); a suffix (0.5.3.6-miku) counts as a test version of 0.5.3.6, so lower than it.
# --notes: the release notes (the handheld shows their first paragraph). --prerelease: a test version (offered only
# with Settings' Test versions on). --image: the card image (banana-<board>.img.gz) attached too.
# Needs gh (GitHub CLI) signed in (gh auth login), and the commit built pushed.
set -e
REPO=${BANANA_RELEASE_REPO:-March93B/BananaMiku}
HERE=$(cd "$(dirname "$0")/.." && pwd)
NOTES=; PRE=; IMAGE=; BOARDS=
while [ $# -gt 0 ]; do
    case $1 in
    --notes) NOTES=$2; shift ;;
    --prerelease) PRE=--prerelease ;;
    --image) IMAGE=1 ;;
    -*) echo "usage: $0 [--notes <file>] [--prerelease] [--image] [board...]" >&2; exit 2 ;;
    *) BOARDS="$BOARDS $1" ;;
    esac
    shift
done
BOARDS=${BOARDS:-rgds-plus}
VERSION=$(cat "$HERE/VERSION")
TAG=v$VERSION
command -v gh >/dev/null || { echo "gh (GitHub CLI) is needed: https://cli.github.com" >&2; exit 1; }
case $VERSION in
*-*) [ -n "$PRE" ] || echo "warning: $VERSION has a suffix, so a handheld on ${VERSION%%-*} won't take it as newer" >&2 ;;
esac
[ -z "$NOTES" ] || [ -f "$NOTES" ] || { echo "no notes file $NOTES" >&2; exit 1; }
gh release view "$TAG" --repo "$REPO" >/dev/null 2>&1 && { echo "$REPO already has a release $TAG: raise VERSION" >&2; exit 1; }
# the release's tag on the commit built, which GitHub must have
SHA=$(git -C "$HERE" rev-parse HEAD)
git -C "$HERE" fetch -q origin
git -C "$HERE" branch -r --contains "$SHA" | grep -q 'origin/' || { echo "push $SHA to origin first" >&2; exit 1; }
[ -z "$(git -C "$HERE" status --porcelain --untracked-files=no)" ] ||
    echo "warning: changes not committed; the release is tagged at $SHA, which doesn't have them" >&2

OUT=$(mktemp -d); trap 'rm -rf "$OUT"' EXIT
FILES=
for b in $BOARDS; do
    IMGS=$HERE/output/$b/images
    P=$IMGS/banana-$b-$VERSION.update.tar
    [ -f "$P" ] || { echo "no $P: build it (make $b) with VERSION $VERSION" >&2; exit 1; }
    # (the version the package carries, which is what it installs as)
    v=$(tar -xOf "$P" "banana-$b-$VERSION.update/VERSION")
    [ "$v" = "$VERSION" ] || { echo "$P carries version $v, not $VERSION" >&2; exit 1; }
    (cd "$IMGS" && sha256sum "banana-$b-$VERSION.update.tar") > "$OUT/SHA256SUMS-$b.txt"
    FILES="$FILES $P $OUT/SHA256SUMS-$b.txt"
    if [ -n "$IMAGE" ]; then
        [ -f "$IMGS/banana-$b.img.gz" ] || { echo "no $IMGS/banana-$b.img.gz" >&2; exit 1; }
        cp "$IMGS/banana-$b.img.gz" "$OUT/banana-$b-$VERSION.img.gz"
        (cd "$OUT" && sha256sum "banana-$b-$VERSION.img.gz") >> "$OUT/SHA256SUMS-$b.txt"
        FILES="$FILES $OUT/banana-$b-$VERSION.img.gz"
    fi
done
if [ -n "$NOTES" ]; then set -- --notes-file "$NOTES"; else set -- --notes "BananaMiku $VERSION"; fi
# shellcheck disable=SC2086
gh release create "$TAG" --repo "$REPO" --target "$SHA" --title "BananaMiku $VERSION" $PRE "$@" $FILES
echo "released $TAG on $REPO: Settings > System > Updates > Check for updates finds it"
