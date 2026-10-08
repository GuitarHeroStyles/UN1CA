# shellcheck shell=sh disable=SC2034
# KernelSU/Magisk module installer for the UN1CA power menu patch (Galaxy A52s 5G).
# Runs inside the KernelSU manager while installing the module zip.
SKIPUNZIP=0

ui_print "- UN1CA advanced power menu patch"

DEVICE="$(getprop ro.product.device)"
case "$DEVICE" in
    a52sxq*) ;;
    *) abort "! Unsupported device: $DEVICE (this patch is only for a52sxq)" ;;
esac

if [ -z "$(getprop ro.unica.version)" ]; then
    abort "! This is not a UN1CA build (ro.unica.version is missing)"
fi
ui_print "- Installed ROM: $(getprop ro.unica.version)"

# The patched APKs must be signed with the same platform key as the installed ROM,
# otherwise the system rejects them (this is the case for official UN1CA builds).
cert_id()
{
    for n in META-INF/CERT.RSA META-INF/CERT.EC META-INF/CERT.DSA; do
        d="$(unzip -p "$1" "$n" 2> /dev/null | head -c 600 | sha256sum | cut -d ' ' -f 1)"
        if [ -n "$d" ] && [ "$d" != "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855" ]; then
            echo "$d"
            return 0
        fi
    done
    return 1
}

if command -v unzip > /dev/null 2>&1 && command -v sha256sum > /dev/null 2>&1; then
    for apk in system/priv-app/SecSettings/SecSettings.apk \
            system/system_ext/priv-app/SystemUI/SystemUI.apk; do
        CURRENT="/$apk"
        OLD="$(cert_id "$CURRENT")"
        NEW="$(cert_id "$MODPATH/$apk")"
        if [ -z "$OLD" ] || [ -z "$NEW" ]; then
            ui_print "! Could not read the signature of $(basename "$apk"), skipping check"
        elif [ "$OLD" != "$NEW" ]; then
            abort "! Signature of $(basename "$apk") does not match the installed ROM. Flash a ROM built from the same repository first."
        else
            ui_print "- Signature OK: $(basename "$apk")"
        fi
    done
else
    ui_print "! unzip/sha256sum not available, skipping the signature check"
fi

set_perm_recursive "$MODPATH/system" 0 0 0755 0644 u:object_r:system_file:s0
ui_print "- Done. Reboot to apply (first boot can take a few minutes)."
