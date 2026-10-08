#!/system/bin/sh
# shellcheck shell=sh
# SecSettings and SystemUI are replaced through this module. PackageManager keeps a parsed copy of
# every system app in /data/system/package_cache and may keep using it even though the file changed,
# so the new activities/permissions are not seen. Once per module version, make the files "new" and
# drop that cache so everything is parsed again at the next boot step.
MODDIR="${0%/*}"
VERSION="$(grep '^versionCode=' "$MODDIR/module.prop" | cut -d '=' -f 2)"
if [ "$(cat "$MODDIR/.pkgcache" 2> /dev/null)" != "$VERSION" ]; then
    find "$MODDIR/system" -type f -exec touch {} +
    rm -rf /data/system/package_cache
    echo "$VERSION" > "$MODDIR/.pkgcache"
fi
