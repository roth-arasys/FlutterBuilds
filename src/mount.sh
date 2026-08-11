#!/bin/zsh
# FlutterBuilds - mount an APFS volume onto each Flutter project's build/ directory.
#
# Cloud clients using the macOS FileProvider (OneDrive) synthesize metadata that makes
# codesign reject Flutter.framework ("resource fork, Finder information, or similar
# detritus not allowed"), which breaks `flutter build ios`. Build output must therefore
# live on a real filesystem. A mount also survives `flutter clean` (EBUSY), unlike a
# symlink, and needs no per-project files.
#
#   mount.sh boot      compact the image if freshly started, then mount everything
#   mount.sh mount     mount every discovered project (idempotent)
#   mount.sh unmount   unmount all our volumes
#   mount.sh clean     drop obsolete volumes, purge shadowed leftovers, compact, remount
#
# Volume names are derived from each project's path relative to the cloud root, which
# makes them unique without a mapping file.
#
# Payload lives OUTSIDE the app bundle: writing into Contents/Resources breaks the code
# signature, and TCC grants (Full Disk Access) are tied to the bundle's code identity.
set -u
emulate -L zsh

# Configuration: Automatically discovers any OneDrive folder in ~/Library/CloudStorage/.
# Multiple custom directories can be passed via FLUTTERBUILDS_CLOUD_DIR separated by colons (:).
typeset -a CLOUD_DIRS
if [[ -n ${FLUTTERBUILDS_CLOUD_DIR:-} ]]; then
  CLOUD_DIRS=(${(s<:>)FLUTTERBUILDS_CLOUD_DIR})
else
  CLOUD_DIRS=("$HOME/Library/CloudStorage"/OneDrive-*(N/))
  if (( ${#CLOUD_DIRS} == 0 )); then
    CLOUD_DIRS=("$HOME/Library/CloudStorage")
  fi
fi

DATA_DIR="$HOME/Library/Application Support/FlutterBuilds"
IMG="$DATA_DIR/FlutterBuilds.sparsebundle"
LOG="$DATA_DIR/mount.log"
SIZE=200g

mkdir -p "$DATA_DIR"
exec >> >(tee -a "$LOG") 2>&1
echo "--- $(date) | ${1:-boot} ---"

die() { echo "ERROR: $*" >&2; exit 1 }

# A TCC denial must not look like "no projects found": the find(1) command yields
# an empty list on permission errors, which would silently skip every mount.
require_access() {
  (( ${#CLOUD_DIRS} > 0 )) || die "No OneDrive or cloud folders found in $HOME/Library/CloudStorage"
  local cdir readable=0
  for cdir in "${CLOUD_DIRS[@]}"; do
    if [[ -d $cdir ]] && ls "$cdir" >/dev/null 2>&1; then
      readable=1
      break
    fi
  done
  (( readable )) || die \
    "cannot read cloud storage folder - grant FlutterBuilds.app Full Disk Access (System Settings > Privacy & Security)"
}

ensure_image() {
  [[ -d $IMG ]] && return
  echo "creating sparse bundle at $IMG"
  hdiutil create -size $SIZE -type SPARSEBUNDLE -fs APFS \
    -volname FlutterBuilds "${IMG%.sparsebundle}" -quiet || die "cannot create $IMG"
}

img_attached() { hdiutil info | grep -q "$IMG" }

CREF=""
resolve_container() {
  img_attached || hdiutil attach "$IMG" -nomount -quiet || die "attach failed"
  local dev=$(hdiutil info | awk -v i="$IMG" '$0 ~ i {f=1} f && /GUID_partition_scheme/ {print $1; exit}')
  [[ -n $dev ]] || die "no block device for image"
  CREF=$(diskutil apfs list | grep -B8 "Physical Store ${dev#/dev/}s2" \
    | awk '/APFS Container Reference/{print $NF}' | tail -1)
  [[ -n $CREF ]] || die "no APFS container on $dev"
}

# Emits "<diskIdentifier>\t<volume name>" per volume. diskutil draws a tree, so lines
# carry leading "|+-<>" characters; the device is matched by pattern rather than field
# index, and the trailing "(Case-insensitive)" suffix is stripped from the name.
volume_table() {
  diskutil apfs list "$CREF" | awk '
    {
      line = $0
      gsub(/^[ \t|+<>-]+/, "", line)
      if (line ~ /^APFS Volume Disk \(Role\):/) {
        if (match(line, /disk[0-9]+s[0-9]+/)) dev = substr(line, RSTART, RLENGTH)
      } else if (line ~ /^Name:/) {
        name = line
        sub(/^Name:[ \t]*/, "", name)
        sub(/ \(Case-[^)]*\)$/, "", name)
        if (dev != "") { print dev "\t" name; dev = "" }
      }
    }'
}

vol_dev()   { volume_table | awk -F'\t' -v n="$1" '$2 == n {print $1; exit}' }
is_mounted() { mount | grep -qF " $1 " }

# Discover every Flutter project in any cloud folder.
# Prunes caches and build/ - the latter matters because build/ may be one of our mounts.
typeset -A EXPECTED    # volume name -> project path
plan() {
  require_access
  EXPECTED=()
  local pubspec proj name cdir rel_path
  for cdir in "${CLOUD_DIRS[@]}"; do
    [[ -d $cdir ]] || continue
    while IFS= read -r pubspec; do
      proj="${pubspec:h}"
      [[ -d $proj/ios || -d $proj/macos ]] || continue      # needs a Darwin target
      rel_path="${proj#$HOME/Library/CloudStorage/}"
      rel_path="${rel_path#$cdir/}"
      name="${${rel_path}//\//_}-build"   # path-derived: unique by construction
      EXPECTED[$name]="$proj"
    done < <(find "$cdir" -maxdepth 6 \
        \( -name .pub-cache -o -name pubCache -o -name build -o -name Pods \
           -o -name .symlinks -o -name .git -o -name node_modules -o -name ephemeral \) -prune \
        -o -name pubspec.yaml -print 2>/dev/null)
  done
  echo "discovered ${#EXPECTED} project(s)"
}

do_mount() {
  plan
  (( ${#EXPECTED} > 0 )) || die "no Flutter projects discovered - refusing to continue"
  ensure_image
  resolve_container
  local name proj mp vdev
  for name proj in ${(kv)EXPECTED}; do
    mp="$proj/build"
    is_mounted "$mp" && continue
    vdev=$(vol_dev "$name")
    if [[ -z $vdev ]]; then
      echo "creating volume $name"
      diskutil apfs addVolume "$CREF" APFS "$name" -nomount >/dev/null \
        || { echo "addVolume $name failed"; continue }
      vdev=$(vol_dev "$name")
    fi
    [[ -n $vdev ]] || { echo "volume $name not found in container"; continue }
    mkdir -p "$mp"
    if mount_apfs -o nobrowse,noowners "/dev/$vdev" "$mp"; then
      echo "mounted $name -> $mp"
    else
      echo "MOUNT FAILED $name -> $mp (build output would land in OneDrive - fix before building)"
    fi
  done
}

do_unmount() {
  img_attached || { echo "image not attached - nothing to unmount"; return }
  resolve_container
  local dev name mp
  volume_table | while IFS=$'\t' read -r dev name; do
    mp=$(mount | awk -v d="/dev/$dev" '$1 == d { sub(/^[^ ]+ on /, ""); sub(/ \([^(]*\)$/, ""); print }')
    [[ -n $mp ]] || continue
    umount "$mp" && echo "unmounted $mp" || echo "failed to unmount $mp"
  done
}

# Deletes volumes whose project no longer exists. Guarded by a non-empty discovery so a
# transient TCC or OneDrive hiccup cannot wipe every volume.
drop_obsolete() {
  plan
  (( ${#EXPECTED} > 0 )) || die "refusing cleanup: no projects discovered"
  resolve_container
  local dev name
  volume_table | while IFS=$'\t' read -r dev name; do
    [[ $name == *-build ]] || continue          # never touch the container's root volume
    [[ -n ${EXPECTED[$name]:-} ]] && continue
    echo "obsolete volume $name ($dev) - deleting"
    diskutil apfs deleteVolume "$dev" >/dev/null || echo "failed to delete $dev"
  done
}

# Removes files sitting in the *shadowed* build/ directories inside the cloud folder.
# Only ever runs while unmounted - a mount hides those files, so purging a mounted path
# would delete the fresh volume contents instead of the stale cloud leftovers.
purge_shadowed() {
  local name proj mp
  for name proj in ${(kv)EXPECTED}; do
    mp="$proj/build"
    is_mounted "$mp" && { echo "skip purge (still mounted): $mp"; continue }
    [[ -d $mp ]] || continue
    if [[ -n $(ls -A "$mp" 2>/dev/null) ]]; then
      echo "purging stale cloud leftovers in $mp"
      find "$mp" -mindepth 1 -delete 2>/dev/null || true
    fi
  done
}

do_clean() {
  do_unmount        # purging and compacting are only safe while nothing is mounted
  drop_obsolete
  purge_shadowed
  compact_image
  do_mount
}

compact_image() {
  [[ -d $IMG ]] || return
  img_attached && { hdiutil detach "$CREF" -quiet 2>/dev/null || hdiutil detach "$CREF" -force -quiet 2>/dev/null }
  sleep 1
  echo "compacting image (before: $(du -sh "$IMG" | cut -f1))"
  hdiutil compact "$IMG" -quiet 2>&1 | tail -2
  echo "compacted (after: $(du -sh "$IMG" | cut -f1))"
  CREF=""
}

case ${1:-boot} in
  # Login path: nothing is attached right after a fresh start, which is exactly the only
  # moment compaction is possible - so reclaim slack there and nowhere else.
  boot)
    if img_attached; then
      echo "image already attached - mounting only, not tearing down volumes in use"
      do_mount
    else
      ensure_image
      do_clean
    fi
    ;;
  mount)   do_mount ;;
  unmount) do_unmount ;;
  clean)   do_clean ;;
  *) die "usage: $0 [boot|mount|unmount|clean]" ;;
esac
echo "done."
