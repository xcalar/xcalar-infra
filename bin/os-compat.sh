#!/bin/bash

# shellcheck disable=SC1091
#. infra-sh-lib

warn() {(set +x
    if test -t 2; then
        YELLOW='\e[33m'
        RESET='\e[0m'
        echo >&2 '\e[33m[WARN]\e[0m' "$@"
    else
        echo >&2 '[WARN] ' "$@"
    fi
)}

error() {(set +x
    if test -t 2; then
        RED='\e[31m'
        RESET='\e[0m'
        echo >&2 -e "${RED}[ERROR]${RESET} " "$@"
    else
        echo >&2 '[ERROR] ' "$@"
    fi
)}

say() {
    echo >&2 "$1"
}

die() {
    error "$1"
    exit 1
}

if [[ $OSTYPE =~ darwin ]]; then
    please_install() {
        say
        say "You need '$1'. The easiest way to install '$1' is via 'brew'"
        if ! command -v brew >/dev/null && [ "$brew_warn" != true ]; then
            brew_warn=true
            say "Alas, you need to install 'brew', a package manager for OSX"
            say
            # shellcheck disable=SC2016
            echo >&2 '  /usr/bin/ruby -e "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/master/install)"'
            say
            say "For more information and detailed instructions on Brew see:"
            say "$BREW_WIKI"
            say
            say "Once you have it, run:"

        else
            say "Try running the following:"
        fi

        say
        say " brew update"
        say " brew install ${2:-$1}"
        if [ -n "$2" ] || [[ $1 =~ gnu ]]; then
            return
        fi
        if [[ $1 =~ ^g ]]; then
            say " or brew install gnu-${1#g}"
        fi
    }

    date() {
        if command -v gdate >/dev/null; then
            gdate "$@"
        else
            date "$@"
        fi
    }

    sort() {
        if command -v gsort >/dev/null; then
            gsort "$@"
        else
            sort "${@//-V/}"
        fi
    }

    mountpoint() {
        if [ "$1" = -q ]; then
            shift
        fi
        if ! test -d "$1"; then
            return 1
        fi
        diskutil info "$1" >/dev/null
    }

    touch() {
        gtouch "$@"
    }

    stat() {
        gstat "$@"
    }

    sed() {
        gsed "$@"
    }

    readlink() {
        greadlink "$@"
    }

    sha256sum() {
        shasum -a 256 "$@"
    }

    sha1sum() {
        shasum -a 1 "$@"
    }

    tar() {
        gtar "$@"
    }

    sysctl_kv() {
        sysctl -n "$1"
    }

    numcpu() {
        sysctl_kv 'machdep.cpu.cores_per_package'
    }

    # in bytes
    memtotal() {
        sysctl_kv 'hw.memsize'
    }

    # in bytes
    memfree() {
        local bytes
        bytes=$(memtotal)
        echo $((bytes * 70 / 100))
    }

    swaptotal() {
        echo 0
    }

    swapfree() {
        echo 0
    }

    # shellcheck disable=SC2164
    readlink_f() {
        local target="$1"
        local oldpwd
        oldpwd="$(pwd)"

        cd "$(dirname $target)"
        target="$(basename $target)"

        # Iterate down a (possible) chain of symlinks
        while [ -L "$target" ]; do
            target="$(readlink $target)"
            cd "$(dirname $target)"
            target="$(basename $target)"
        done

        echo "$(pwd -P)/$target"
        cd "$oldpwd"
    }

else
    please_install() {
        say ""
        if command -v apt-get >/dev/null; then
            say "You need to install $1. Try 'sudo apt-get update && sudo apt-get install -y ${2:-$1}'"
        else
            say "You need to install $1. Try 'sudo yum install -y --enablerepo=\"xcalar-*\" ${2:-$1}'"
        fi
    }

    readlink_f() {
        readlink -f "$@"
    }

    # in bytes
    _meminfo() {
        local kbytes
        kbytes=$(awk '/^'$1':/{print $2}' /proc/meminfo)
        echo $((kbytes * 1000))
    }

    memtotal() {
        _meminfo MemTotal
    }

    # in bytes
    memfree() {
        _meminfo MemFree
    }

    memavail() {
        _meminfo MemAvailable
    }

    numcpu() {
        nproc
    }

    swaptotal() {
        _meminfo SwapTotal
    }

    swapfree() {
        _meminfo SwapFree
    }
fi

have_command() {
    command -v "$1" >/dev/null
}

please_have() {
    if ! have_command "$1"; then
        please_install "$@"
        UNMET_DEPS+=("$1")
        return 1
    fi
}
