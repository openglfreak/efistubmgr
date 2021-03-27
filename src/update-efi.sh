#!/bin/sh
# Copyright (C) 2021 Torge Matthies
#
# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at https://mozilla.org/MPL/2.0/.
#
# Author contact info:
#   E-Mail address: openglfreak@googlemail.com
#   PGP key fingerprint: 0535 3830 2F11 C888 9032 FAD2 7C95 CD70 C9E8 438D

set -e 2>/dev/null ||:
set +C 2>/dev/null ||:
set +f 2>/dev/null ||:
set -u 2>/dev/null ||:

# zsh: Force word splitting.
setopt SH_WORD_SPLIT 2>/dev/null ||:
# zsh: Don't exit when a glob doesn't match.
unsetopt NOMATCH 2>/dev/null ||:

# description:
#   Escapes a string for usage in a sed pattern.
#   Sed expression copied from https://stackoverflow.com/a/2705678
# params:
#   [literal]: string
#     The string to escape. If omitted it's read from stdin
#   [separator]: char
#     The separator char. Defaults to a / (slash)
# outputs:
#   The escaped string
sed_escape_pattern() {
    if [ $# -gt 2 ]; then
        echo 'sed_escape_pattern: Too many arguments' >&2
        return 1
    fi
    if [ $# -ge 1 ]; then
        # Shellcheck bug.
        # shellcheck disable=SC2221,SC2222
        case "${2:-}" in
           ??*)
               echo 'sed_escape_pattern: Separator too long' >&2
               return 2;;
           []\\\$\*\.^[]) set -- "$1" '';;
           ''|*) set -- "$1" "${2:-/}"
        esac
        # shellcheck disable=SC1003
        printf '%s\n' "$1" | sed -e 's/[]\\'"$2"'$*.^[]/\\&/g' -e '$!s/$/\\/'
    else
        sed -e 's/[]\\/$*.^[]/\\&/g' -e '$!s/$/\\/'
    fi
}

# description:
#   Finds a boot entry by the label and returns the entry's bootnum
# params:
#   name: string
#     The label of the boot entry to find
# outputs:
#   The bootnums of the found boot entries as 4-digit hexadecimal numbers,
#   one per line, or nothing if no entry is found
find_bootnum_from_label() {
    if [ $# -ne 1 ]; then
        if [ $# -lt 1 ]; then
            echo 'find_bootnum_from_label: Not enough arguments' >&2
            return 1
        else
            echo 'find_bootnum_from_label: Too many arguments' >&2
            return 2
        fi
    fi
    LC_ALL=C efibootmgr | sed -n -e 's/^Boot\([0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f]\)[* ] '"$(sed_escape_pattern "$1")"'$/\1/p'
}

# description:
#   Deletes a list of boot entries by their bootnums
# params:
#   [bootnums...]: string
#     The bootnums of the boot entries to delete
delete_bootnums() {
    while [ $# -ge 1 ]; do
        efibootmgr --bootnum "$1" --delete-bootnum >/dev/null || return
        shift
    done
}

# description:
#   Finds a boot entry by the label and deletes it
# params:
#   name: string
#     The label of the boot entry to delete
# outputs:
#   The number of boot entries found
delete_bootentry_by_label() {
    if [ $# -ne 1 ]; then
        if [ $# -lt 1 ]; then
            echo 'delete_bootentry_by_label: Not enough arguments' >&2
            return 1
        else
            echo 'delete_bootentry_by_label: Too many arguments' >&2
            return 2
        fi
    fi
    set -f 2>/dev/null ||:
    # shellcheck disable=SC2046
    set -- $(find_bootnum_from_label "$1")
    set +f 2>/dev/null ||:
    printf '%i\n' $#
    delete_bootnums ${1+"$@"}
}

# description:
#   Creates a new boot entry with the specified parameters.
#   See efibootmgr(8) for the default values of optional parameters.
#   Empty optional parameters are handled like unset.
#   This function creates a new entry even when one with the same name
#   already exists. If this is not what you want, see update_bootentry.
# params:
#   label: string
#     The label of the boot entry
#   loader: string
#     The loader for the boot entry
#   [cmdline]: string
#     Command line arguments for the loader
#   [disk]: string
#     The disk containing the loader
#   [part]: string
#     The partition containing the loader
# outputs:
#   The efibootmgr output
create_bootentry() {
    if [ $# -lt 2 ]; then
        echo 'create_bootentry: Not enough arguments' >&2
        return 1
    fi
    if [ $# -gt 5 ]; then
        echo 'create_bootentry: Too many arguments' >&2
        return 2
    fi

    efibootmgr --create ${4:+--disk} ${4:+"$4"} \
               ${5:+--part} ${5:+"$5"} \
               --label "$1" \
               --loader "$2" \
               ${3:+--unicode} ${3:+"$3"}
}

# description:
#   Creates or updates a boot entry with new parameters.
#   See efibootmgr(8) for the default values of optional parameters.
#   Empty optional parameters are handled like unset
# params:
#   label: string
#     The label of the boot entry
#   loader: string
#     The loader for the boot entry
#   [cmdline]: string
#     Command line arguments for the loader
#   [disk]: string
#     The disk containing the loader
#   [part]: string
#     The partition containing the loader
# outputs:
#   The efibootmgr output
update_bootentry() {
    if [ $# -lt 2 ]; then
        echo 'update_bootentry: Not enough arguments' >&2
        return 1
    fi
    if [ $# -gt 5 ]; then
        echo 'update_bootentry: Too many arguments' >&2
        return 2
    fi

    delete_bootentry_by_label "$1" >/dev/null || return
    create_bootentry "$@"
}

_is_dry_run() { [ "x${dry_run:-${DRY_RUN:-0}}" = 'x1' ] || return; }
_is_verbose() { [ "x${verbose:-${VERBOSE:-0}}" = 'x1' ] || return; }

_is_true() {
    set -- "$(printf '%s\n' "$1" | tr '[:upper:]' '[:lower:]')"
    case "$1" in
        true|1|y|yes|on) :;;
        *) return 1
    esac
}

_load_config() {
    ! _is_verbose || printf 'Loading config file %s\n' "$1"
    # shellcheck source=examples/archlinux-default-config.conf
    # shellcheck disable=SC1091,SC2034
    if ! . "$1"; then
        printf 'error: Error while processing config file %s\n' "$1" >&2
        return 1
    fi
}

_load_configs_dir() {
    if [ -e "$1/efistubmgr.conf" ]; then
        _load_config "$1/efistubmgr.conf"
    fi
    for config_file in "$1/efistubmgr.conf.d"/*.conf; do
        [ -e "${config_file}" ] || continue
        _load_config "${config_file}" 2>&3 3>&-
    done 3>&2 2>/dev/null ||:
}

# shellcheck disable=SC2120
_load_configs() {
    if [ "x${single_config+set}" = 'xset' ]; then
        # shellcheck disable=SC1090
        if ! . "${single_config}"; then
            printf 'error: Error while processing config file %s\n' "${single_config}" >&2
            return 1
        fi
        return
    fi

    ! [ -d /boot ] || _load_configs_dir /boot
    set -f 2>/dev/null ||:
    IFS=':' eval 'set -- ${XDG_CONFIG_DIRS:-/etc/xdg}'
    set +f 2>/dev/null ||:
    i=$#; while [ "${i}" -ge 1 ]; do
        eval "_load_configs_dir \"\${${i}}\""
        i="$((i-1))"
    done
}

_create_data_dir() {
    if ! _is_dry_run; then
        mkdir -p /var/lib || return
        # shellcheck disable=SC2174
        mkdir -p -m 700 /var/lib/efistubmgr
    fi
}

_check_managed_entry_list_writable() {
    if ! _is_dry_run; then
        if [ -e /var/lib/efistubmgr/managed_entries ]; then
            if ! [ -w /var/lib/efistubmgr/managed_entries ]; then
                echo 'error: State file not writable' >&2
                return 1
            fi
        elif [ -e /var/lib/efistubmgr ]; then
            if ! [ -d /var/lib/efistubmgr ]; then
                echo 'error: State directory of wrong type' >&2
                return 2
            fi
            if ! [ -w /var/lib/efistubmgr ]; then
                echo 'error: State directory not writable' >&2
                return 3
            fi
        elif [ -e /var/lib ]; then
            if ! [ -d /var/lib ]; then
                echo 'error: /var/lib of wrong type' >&2
                return 4
            fi
            if ! [ -w /var/lib ]; then
                echo 'error: /var/lib not writable' >&2
                return 5
            fi
        else
            echo 'error: /var/lib does not exist' >&2
            return 6
        fi
    fi
}

_load_managed_entry_list() {
    _check_managed_entry_list_writable || return
    ! _is_verbose || echo 'Loading managed entry list'
    if [ -e /var/lib/efistubmgr/managed_entries ]; then
        if ! managed_entries="$(cat /var/lib/efistubmgr/managed_entries)"; then
            echo 'error: State file not readable' >&2
            return 1
        fi
    else
        managed_entries=
    fi
}

_update_entry() {
    eval "label=\"\${LABEL_$1:-}\""
    ! _is_verbose || printf 'Creating/updating boot entry "%s"\n' "${label}"
    eval "kernel=\"\${KERNEL_$1:-}\""
    eval "cmdline=\"\${CMDLINE_$1:-\${CMDLINE:-}}\""
    eval "no_autodetect_ucode=\"\${NO_AUTODETECT_UCODE_$1:-\${NO_AUTODETECT_UCODE:-}}\""

    if eval "[ \"x\${INITRD_$1+set}\" = 'xset' ]"; then
        eval "initrds=\"initrd=\\\\\${INITRD_$1}\""
    else
        initrds=
        j=0; while eval "[ \"x\${INITRD_$1_${j}+set}\" = 'xset' ]"; do
            eval "initrds=\"\${initrds} initrd=\\\\\${INITRD_$1_${j}}\""
            j="$((j+1))"
        done
        initrds="${initrds# }"
    fi

    # shellcheck disable=SC2154
    if [ "x${initrds:+set}" = 'xset' ] && _is_true "${no_autodetect_ucode}"; then
        if [ "x${ucode_initrds+set}" = 'xset' ]; then
            ! _is_verbose || echo 'Searching for microcode initrds'
            ucode_initrds=
            for ucode_initrd in /boot/*-ucode.img; do
                [ -e "${ucode_initrd}" ] || continue
                ! _is_verbose || printf 'Found microcode initrd %s\n' "${ucode_initrd}"
                ucode_initrds="initrd=\\${ucode_initrd#/boot/} ${ucode_initrds}"
            done
        fi
        initrds="${ucode_initrds}${initrds}"
    fi

    if [ "x${initrds:+set}" = 'xset' ]; then
        cmdline="root=UUID=${rootuuid=$(findmnt -vkno UUID /)} rootfstype=${rootfstype=$(findmnt -vkno FSTYPE /)} rootflags=${rootflags=$(findmnt -vkno OPTIONS /)} ${initrds} ${cmdline}"
    else
        cmdline="root=${rootdev=$(findmnt -vkno SOURCE /)} rootfstype=${rootfstype=$(findmnt -vkno FSTYPE /)} rootflags=${rootflags=$(findmnt -vkno OPTIONS /)} ${cmdline}"
    fi

    if ! _is_dry_run; then
        # shellcheck disable=SC2154
        if ! update_bootentry "${label}" "\\${kernel}" "${cmdline}" >/dev/null; then
            printf 'error: Failed to create/update boot entry "%s"\n' "${label}" >&2
            return 1
        fi
    fi
}

_update_entries() {
    _new_managed_entries=
    i=0; while eval "[ \"x\${LABEL_${i}+set}\" = 'xset' ]"; do
        _update_entry "${i}" || return
        _new_managed_entries="${_new_managed_entries}
${label}"
        i="$((i+1))"
    done
    new_managed_entries="${_new_managed_entries#?}"
}

_get_tmpdir() {
    if [ "x${XDG_RUNTIME_DIR:+set}" = 'xset' ]; then
        tmpdir="${XDG_RUNTIME_DIR}"
        # shellcheck disable=SC2174
        mkdir -p -m 700 "${tmpdir}"
    else
        tmpdir="${TMPDIR:-${TEMPDIR:-/tmp}}"
        # shellcheck disable=SC2174
        mkdir -p -m 777 "${tmpdir}"
    fi
}

_remove_old_entries() {
    _get_tmpdir || return
    printf '%s\n' "${managed_entries}" | LC_ALL=C sort -u >"${tmpdir}/efistubmgr-old-managed" || return
    printf '%s\n' "${new_managed_entries}" | LC_ALL=C sort -u >"${tmpdir}/efistubmgr-new-managed" || return
    entries_to_remove="$(LC_ALL=C comm -23 -- "${tmpdir}/efistubmgr-old-managed" "${tmpdir}/efistubmgr-new-managed")"
    [ "x${entries_to_remove:+set}" = 'xset' ] || return 0

    _failed_to_remove=
    while IFS= read -r label; do
        ! _is_verbose || printf 'Removing boot entry "%s"\n' "${label}"
        if ! _is_dry_run; then
            if ! delete_bootentry_by_label "${label}" >/dev/null; then
                ! _is_verbose || printf 'Failed to remove boot entry "%s"\n' "${label}"
                _failed_to_remove="${_failed_to_remove}${label}
"
            fi
        fi
    done <<EOF
${entries_to_remove}
EOF
    new_managed_entries="${_failed_to_remove}${new_managed_entries}"
}

_write_new_managed_entry_list() {
    ! _is_verbose || echo 'Saving new managed entry list'
    if ! _is_dry_run; then
        if ! [ -e /var/lib/efistubmgr ]; then
            # shellcheck disable=SC2174
            mkdir -p -m 755 /var/lib/efistubmgr || return
        fi
        if ! printf '%s\n' "${new_managed_entries}" >/var/lib/efistubmgr/managed_entries; then
            echo 'error: Could not write new managed boot entry list' >&2
            return 1
        fi
    fi
}

_update_entries_and_state() {
    _create_data_dir || return
    _load_managed_entry_list || return
    if _update_entries; then
        _remove_old_entries
    else
        if [ "x${new_managed_entries:+set}" = 'xset' ]; then
            new_managed_entries="${managed_entries}
${new_managed_entries}"
        else
            new_managed_entries="${managed_entries}"
        fi
    fi
    _write_new_managed_entry_list
}

# description:
#   Unsets the variables _LABEL, _KERNEL, _CMDLINE, _NO_AUTODETECT_UCODE and
#   _INITRD (or if unset _INITRD_*).
# shellcheck disable=SC2120
clear_loaded_data() {
    if [ $# -ne 0 ]; then
        echo 'clear_loaded_data: Too many arguments' >&2
        return 1
    fi

    set -- LABEL KERNEL CMDLINE NO_AUTODETECT_UCODE
    while [ $# -ge 1 ]; do
        if eval "[ \"x\${_${1}+set}\" = 'xset' ]"; then
            eval "unset _${1}"
        fi
        shift
    done
    unset _INITRD
    set -- 0
    while eval "[ \"x\${_INITRD_${1}+set}\" = 'xset' ]"; do
        eval "unset \${_INITRD_${1}}"
        set -- "$(($1+1))"
    done
}

# description:
#   Clears the data from a boot entry slot. Note that this will prevent any
#   following boot entries from being processed, until the entry is reinstated.
# params:
#   slot: integer
#     The boot entry slot to clear the data from
clear_entry_data() {
    if [ $# -ne 1 ]; then
        if [ $# -lt 1 ]; then
            echo 'clear_entry_data: Not enough arguments' >&2
            return 1
        else
            echo 'clear_entry_data: Too many arguments' >&2
            return 2
        fi
    fi

    set -- "$1" ''
    set -- "$1" "$(($1))" 2>/dev/null ||:
    if ! [ "$1" -eq "$2" ] 2>/dev/null; then
        printf 'clear_entry_data: Not a number: "%s"\n' "$1" >&2
        return 3
    fi
    shift

    set -- "$1" LABEL "$1" KERNEL "$1" CMDLINE "$1" NO_AUTODETECT_UCODE "$1"
    while [ $# -ge 2 ]; do
        if eval "[ \"x\${${2}_${1}+set}\" = 'xset' ]"; then
            eval "unset ${2}_${1}"
        fi
        shift 2
    done
    eval "unset INITRD_${1}"
    set -- "$1" 0
    while eval "[ \"x\${INITRD_${1}_${2}+set}\" = 'xset' ]"; do
        eval "unset INITRD_${1}_${2}"
        set -- "$1" "$(($2+1))"
    done
}

# description:
#   Copies the variables _LABEL, _KERNEL, _CMDLINE, _NO_AUTODETECT_UCODE and
#   _INITRD (or if unset _INITRD_*) to the specified boot entry slot.
# params:
#   slot: integer
#     The boot entry slot to write to
save_entry_data() {
    if [ $# -ne 1 ]; then
        if [ $# -lt 1 ]; then
            echo 'save_entry_data: Not enough arguments' >&2
            return 1
        else
            echo 'save_entry_data: Too many arguments' >&2
            return 2
        fi
    fi

    set -- "$1" ''
    set -- "$1" "$(($1))" 2>/dev/null ||:
    if ! [ "$1" -eq "$2" ] 2>/dev/null; then
        printf 'save_entry_data: Not a number: "%s"\n' "$1" >&2
        return 3
    fi
    shift

    clear_entry_data "$1" || return

    set -- "$1" LABEL "$1" KERNEL "$1" CMDLINE "$1" NO_AUTODETECT_UCODE "$1"
    while [ $# -ge 2 ]; do
        if eval "[ \"x\${_${2}+set}\" = 'xset' ]"; then
            eval "${2}_${1}=\"\${_${2}}\""
        fi
        shift 2
    done
    if [ "x${_INITRD+set}" = 'xset' ]; then
        eval "INITRD_${1}=\"\${_INITRD}\""
    else
        set -- "$1" 0
        while eval "[ \"x\${_INITRD_${2}+set}\" = 'xset' ]"; do
            eval "INITRD_${1}_${2}=\"\${_INITRD_${2}}\""
            set -- "$1" "$(($2+1))"
        done
    fi
}

# description:
#   Loads the data from the specified boot entry slot into the variables _LABEL,
#   _KERNEL, _CMDLINE, _NO_AUTODETECT_UCODE and _INITRD (or if unset _INITRD_*).
# params:
#   slot: integer
#     The boot entry slot to read from
load_entry_data() {
    if [ $# -ne 1 ]; then
        if [ $# -lt 1 ]; then
            echo 'load_entry_data: Not enough arguments' >&2
            return 1
        else
            echo 'load_entry_data: Too many arguments' >&2
            return 2
        fi
    fi

    set -- "$1" ''
    set -- "$1" "$(($1))" 2>/dev/null ||:
    if ! [ "$1" -eq "$2" ] 2>/dev/null; then
        printf 'load_entry_data: Not a number: "%s"\n' "$1" >&2
        return 3
    fi
    shift

    clear_loaded_data || return

    set -- "$1" LABEL "$1" KERNEL "$1" CMDLINE "$1" NO_AUTODETECT_UCODE "$1"
    while [ $# -ge 2 ]; do
        if eval "[ \"x\${${2}_${1}+set}\" = 'xset' ]"; then
            eval "_${2}=\"\${${2}_${1}}\""
        fi
        shift 2
    done
    if eval "[ \"x\${INITRD_${1}+set}\" = 'xset' ]"; then
        eval "_INITRD=\"\${INITRD_${1}}\""
    else
        set -- "$1" 0
        while eval "[ \"x\${INITRD_${1}_${2}+set}\" = 'xset' ]"; do
            eval "_INITRD_${2}=\"\${INITRD_${1}_${2}}\""
            set -- "$1" "$(($2+1))"
        done
    fi
}

# description:
#   Adds a new boot entry in the first free slot by copying the variables
#   _LABEL, _KERNEL, _CMDLINE, _NO_AUTODETECT_UCODE and _INITRD (or if unset
#   _INITRD_*) to the variables of the first slot with an unset LABEL. If the
#   slot directly following the chosen boot entry slot contains data, it will
#   be cleared.
add_boot_entry() {
    if [ $# -ne 0 ]; then
        echo 'add_boot_entry: Too many arguments' >&2
        return 1
    fi

    set -- 0
    while eval "[ \"x\${LABEL_${1}+set}\" = 'xset' ]"; do
        set -- "$(($1+1))"
    done
    clear_entry_data "$(($1+1))" || return
    save_entry_data "$1" || return
    clear_loaded_data
}

# description:
#   The main function of the program
# params:
#   [options...]: string
#     The command line options for the program
# outputs:
#   Log messages, if enabled
main() {
    while [ $# -ge 1 ]; do
        case "$1" in
            -c|--config)
                single_config="$2"
                shift 2;;
            -d|--dry-run)
                DRY_RUN=1
                shift;;
            -v|--verbose)
                VERBOSE=1
                shift;;
            -h|--help)
                cat <<EOF
Usage: ${0##*/} [options]

Options:
  -c, --config <file>   Use an alternate config file
  -d, --dry-run         Do not update any files or efi variables
  -v, --verbose         Output status messages while working
  -h, --help            Show this help message
EOF
                return;;
            *)
                printf 'error: Unrecognized parameter: %s\n' "$1"
                return 1
        esac
    done

    _load_configs || return
    efibootmgr >/dev/null || return
    _update_entries_and_state
}

main ${1+"$@"}
