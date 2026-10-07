# Adds "Recovery", "Download" and "Restart One UI" entries to the power menu.
# Logic ported from Firefds Kit (Apache-2.0, Shauli Bracha).
#
# The new smali classes are generated from templates, with every framework method/field
# descriptor resolved from the decoded framework.jar of the firmware being built.
# If something does not match, the build is aborted instead of shipping a broken framework.
GA_REL="com/samsung/android/globalactions/presentation"
FWJAR="$APKTOOL_DIR/system/framework/framework.jar"
SEDF="$TMP_DIR/powermenu.sed"

# RESOLVE <name> <method> <args-regex> [file]
# Appends the sed rules for the @OP_<name>@ and @REF_<name>@ tokens to $SEDF.
RESOLVE()
{
    local PFX="$1"
    local NAME="$2"
    local ARGS="$3"
    local F="$4"
    local OP="invoke-virtual"
    local LINE
    local CLS

    if [ -z "$F" ]; then
        local MATCHES
        MATCHES="$(grep -rlE "^\.method (.* )?$NAME\(($ARGS)\)" "$FWJAR"/smali*/com/samsung/android/globalactions || true)"
        F="$(grep -m1 "SamsungGlobalActionsPresenter.smali$" <<< "$MATCHES" || true)"
        [ -n "$F" ] || F="$(head -n 1 <<< "$MATCHES")"
    fi

    if [ -z "$F" ]; then
        LOGE "powermenu: method \"$NAME($ARGS)\" not found in framework.jar"
        return 1
    fi

    LINE="$(grep -m1 -E "^\.method (.* )?$NAME\(($ARGS)\)" "$F")"
    CLS="$(grep -m1 "^\.class" "$F" | grep -o "L[^;]*;")"
    if grep -m1 "^\.class" "$F" | grep -q " interface "; then
        OP="invoke-interface"
    fi

    {
        echo "s|@OP_$PFX@|$OP|g"
        echo "s|@REF_$PFX@|$CLS->${LINE##* }|g"
    } >> "$SEDF"
}

# FIND_SMALI <name.smali>
FIND_SMALI()
{
    find "$FWJAR" -type f -path "*/$GA_REL/*" -name "$1" | head -n 1
}

DECODE_APK "system" "system/framework/framework.jar"

PRESENTER="$(FIND_SMALI "SamsungGlobalActionsPresenter.smali")"
ACTIONINFO="$(FIND_SMALI "ActionInfo.smali")"
VIEWMODEL="$(FIND_SMALI "ActionViewModel.smali")"
ITEMVIEW="$(FIND_SMALI "GlobalActionsContentItemView.smali")"
RESFACTORY="$(FIND_SMALI "ResourceFactory.smali")"
RESTYPE="$(FIND_SMALI "ResourceType.smali")"

for f in "$PRESENTER" "$ACTIONINFO" "$VIEWMODEL"; do
    if [ ! -f "$f" ]; then
        ABORT "powermenu: required global actions classes not found in framework.jar" || return 1
    fi
done

# The new class must implement every abstract method of ActionViewModel
IMPLEMENTED=" getActionInfo setActionInfo showBeforeProvisioning getIcon onPress onPressSecureConfirm "
while IFS= read -r m; do
    n="$(sed -E 's/^\.method .* ([^ (]+)\(.*/\1/' <<< "$m")"
    if [[ "$IMPLEMENTED" != *" $n "* ]]; then
        ABORT "powermenu: ActionViewModel has an unhandled abstract method: $m" || return 1
    fi
done < <(grep -E "^\.method .*abstract" "$VIEWMODEL" || true)

ICON_RET="$(grep -m1 -E "^\.method (.* )?getIcon\(\)" "$VIEWMODEL" | sed -E 's/.*\)//')"
if [ -z "$ICON_RET" ]; then
    ABORT "powermenu: ActionViewModel.getIcon() not found" || return 1
fi
if ! grep -q "CENTER_ICON_3P_VIEW" "$(FIND_SMALI "ViewType.smali")"; then
    ABORT "powermenu: ViewType.CENTER_ICON_3P_VIEW not found" || return 1
fi

: > "$SEDF"
echo "s|@ICON_RET@|$ICON_RET|g" >> "$SEDF"
RESOLVE "ISCONF" "isActionConfirming" "" "$PRESENTER" || return 1
RESOLVE "CONFIRM" "confirmAction" "L[^;]*ActionViewModel;" || return 1
RESOLVE "DISMISS" "dismissDialog" "Z" || return 1
RESOLVE "ADD" "addAction" "L[^;]*ActionViewModel;" "$PRESENTER" || return 1
RESOLVE "SETNAME" "setName" "Ljava/lang/(String|CharSequence);" "$ACTIONINFO" || return 1
RESOLVE "SETLABEL" "setLabel" "Ljava/lang/(String|CharSequence);" "$ACTIONINFO" || return 1
RESOLVE "SETDESC" "setDescription" "Ljava/lang/(String|CharSequence);" "$ACTIONINFO" || return 1
RESOLVE "SETVIEWTYPE" "setViewType" "L[^;]*ViewType;" "$ACTIONINFO" || return 1

DEX_ROOT="${PRESENTER%%/$GA_REL/*}"
OUT_PKG="$DEX_ROOT/$GA_REL/viewmodel"
EVAL "mkdir -p \"$OUT_PKG\""

LOG "- Adding power menu classes to /system/system/framework/framework.jar"
EVAL "sed -f \"$SEDF\" \"$MODPATH/framework.jar/UnicaPowerAction.smali.in\" > \"$OUT_PKG/UnicaPowerAction.smali\""
EVAL "sed -f \"$SEDF\" \"$MODPATH/framework.jar/UnicaPowerMenu.smali.in\" > \"$OUT_PKG/UnicaPowerMenu.smali\""

# INJECT <smali> <method signature> <tag> <invoke line>
# Inserts a guarded call before every "return-void" of the method (exceptions are swallowed).
INJECT()
{
    local FILE="$1"
    local SIG="$2"
    local TAG="$3"
    local CALL="$4"

    awk -v SIG="$SIG" -v TAG="$TAG" -v CALL="$CALL" '
        BEGIN { inside = 0; n = 0 }
        /^\.method/ { inside = (index($0, SIG) > 0) }
        /^\.end method/ { inside = 0 }
        inside && /^[[:space:]]*return-void[[:space:]]*$/ {
            print "    :try_start_" TAG n
            print "    " CALL
            print "    :try_end_" TAG n
            print "    .catchall {:try_start_" TAG n " .. :try_end_" TAG n "} :catch_" TAG n
            print $0
            print "    :catch_" TAG n
            print "    move-exception p0"
            print "    return-void"
            n++
            next
        }
        { print }
        END { if (n == 0) exit 3 }
    ' "$FILE" > "$FILE.tmp" || { rm -f "$FILE.tmp"; return 1; }
    mv "$FILE.tmp" "$FILE"
}

LOG "- Hooking SamsungGlobalActionsPresenter.createDefaultActions()"
INJECT "$PRESENTER" "createDefaultActions()V" "unicapm" \
    "invoke-static {p0}, Lcom/samsung/android/globalactions/presentation/viewmodel/UnicaPowerMenu;->addActions(Lcom/samsung/android/globalactions/presentation/SamsungGlobalActionsPresenter;)V" || \
    ABORT "powermenu: failed to hook createDefaultActions()" || return 1

# Icons are optional: without them the entries still work using the default item icon
ICON_OK=false
if [ -f "$ITEMVIEW" ] && [ -f "$RESFACTORY" ] && [ -f "$RESTYPE" ] && \
        grep -q "ID_ICON" "$RESTYPE" && \
        grep -q -E "^\.method (.* )?setViewAttrs\(Landroid/view/View;Z\)V" "$ITEMVIEW"; then
    ITEM_CLS="$(grep -m1 "^\.class" "$ITEMVIEW" | grep -o "L[^;]*;")"
    RT_CLS="$(grep -m1 "^\.class" "$RESTYPE" | grep -o "L[^;]*;")"
    VM_TYPE="$(grep -m1 -E "^\.field .* mViewModel:" "$ITEMVIEW" | sed -E 's/.*mViewModel://')"
    RF_TYPE="$(grep -m1 -E "^\.field .* mResourceFactory:" "$ITEMVIEW" | sed -E 's/.*mResourceFactory://')"
    if [ "$VM_TYPE" ] && [ "$RF_TYPE" ] && \
            RESOLVE "RFGET" "get" "$RT_CLS" "$RESFACTORY"; then
        {
            echo "s|@ITEM_CLS@|$ITEM_CLS|g"
            echo "s|@RT_CLS@|$RT_CLS|g"
            echo "s|@VM_TYPE@|$VM_TYPE|g"
            echo "s|@RF_TYPE@|$RF_TYPE|g"
        } >> "$SEDF"
        ICON_OK=true
    fi
fi

if $ICON_OK; then
    EVAL "sed -f \"$SEDF\" \"$MODPATH/framework.jar/UnicaIconHook.smali.in\" > \"$OUT_PKG/UnicaIconHook.smali\""
    LOG "- Hooking GlobalActionsContentItemView.setViewAttrs()"
    INJECT "$ITEMVIEW" "setViewAttrs(Landroid/view/View;Z)V" "unicaic" \
        "invoke-static {p0, p1}, Lcom/samsung/android/globalactions/presentation/viewmodel/UnicaIconHook;->applyIcon(Ljava/lang/Object;Landroid/view/View;)V" || \
        ABORT "powermenu: failed to hook setViewAttrs()" || return 1
else
    LOGW "powermenu: icon hook not applicable, entries will use the default icon"
fi

unset GA_REL FWJAR SEDF PRESENTER ACTIONINFO VIEWMODEL ITEMVIEW RESFACTORY RESTYPE
unset IMPLEMENTED ICON_RET DEX_ROOT OUT_PKG ICON_OK ITEM_CLS RT_CLS VM_TYPE RF_TYPE
