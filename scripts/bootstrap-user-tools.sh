#!/bin/bash
#
# Installs common packages as static binaries into ~/.local
# to allow for portable container "dev environments"
#
# shellcheck disable=SC2086,SC2046,SC2015

BASE_URL="${BASE_URL:-http://repo.xcalar.net/deps}"

NVIM_VERSION="0.3.4"
TMUX_VERSION="2.8-8"
RUBY_VERSION="2.3.7"
NODE_VERSION="10.15.0"
CADDY_VERSION="0.11.0-103"

FORCE=${FORCE:-false}
PREFIX="${HOME}/.local"
# PREFIX/apps/${app}-${version} contains the app
# PREFIX/bin will have the symlink to the binary form apps/

declare -A VERSIONS=([nvim]=$NVIM_VERSION [tmux]=$TMUX_VERSION [ruby]=$RUBY_VERSION [node]=$NODE_VERSION [caddy]=$CADDY_VERSION)
# shellcheck disable=SC1083
declare -A URLS=([nvim]=${BASE_URL}/nvim-\${version}-linux64.tar.gz
    [tmux]=${BASE_URL}/tmux-\${version}.tar.gz
    [ruby]=${BASE_URL}/portable-ruby-\${version}.x86_64_linux.bottle.tar.gz
    [node]=${BASE_URL}/node-v\${version}-linux-x64.tar.xz
    [caddy]=${BASE_URL}/caddy_\${version}_linux_amd64.tar.gz)

ln_r() {
    if ln --help | grep -q -- --relative; then
        ln -sfnr "$@"
    else
        ln -sfn "$@"
    fi
}

# Install the given app, eg app_install nvim
app_install() {
    prog="$1"
    version="${VERSIONS[$prog]}"
    url="$(eval echo ${URLS[$prog]})"
    app_prefix=${PREFIX}/apps/${prog}-${version}

    mkdir -p "$app_prefix"
    echo >&2 " ==> Installing $1 ($version) from $url"
    install_${prog}
}

# Prefix PATH in ~/.bashrc
prefix_path() {
    local addpath="$1"
    export PATH="${addpath}:$PATH"
    if ! grep 'PATH=' ~/.bashrc | grep -q "$addpath"; then
        echo >&2 "Adding $addpath to your \$PATH"
        echo "export PATH=$addpath:\$PATH" >> ~/.bashrc
    fi
}

have_app() {
    local version=${VERSIONS[$1]}
    if [ -z "$version" ]; then
        echo "ERROR: No version of $1 defined!" >&2
        exit 1
    fi
    if $FORCE; then
        rm -rf ${PREFIX}/apps/${1}-${version}
    fi
    test -e ${PREFIX}/apps/${1}-${version}
}

# ** Don't call install_nvim & friends directly **
# Use app_install nvim
install_nvim() {
    curl -fsSL "$url" | tar zxf - --strip-components=1 -C $app_prefix
    local nvimd=$HOME/.config/nvim
    if test -e $nvimd; then
        test -L $nvimd && rm -f $nvimd || mv -v $nvimd ${nvimd}.bak
    fi
    mkdir -p $HOME/.config $HOME/.vim/backup $HOME/.vim/tmp
    touch $HOME/.vimrc
    ln -sfn ../.vim $nvimd
    ln -sfn ../.vimrc $HOME/.vim/init.vim

    ln_r $app_prefix/bin/nvim $PREFIX/bin/
    cat > $PREFIX/bin/vim <<'VEOF'
#!/bin/bash
DIR="$(cd $(dirname $(readlink -f ${BASH_SOURCE[0]})) && pwd)"
if ldd "$DIR"/nvim 2>&1 | grep -q 'not found'; then
    if test -x /usr/bin/vim; then
        exec /usr/bin/vim "$@"
    fi
    if test -x /usr/bin/vi; then
        exec /usr/bin/vi "$@"
    fi
fi
exec nvim "$@"
VEOF
    chmod +x $PREFIX/bin/vim
    ln -sfn vim $PREFIX/bin/vi

    echo -e 'exec vim -d "$@"' > $PREFIX/bin/vimdiff
    chmod +x $PREFIX/bin/vimdiff
}

install_tmux() {
    curl -fsSL "$url" | tar zxf - -C ${app_prefix}
    ln_r ${app_prefix}/bin/tmux ${PREFIX}/bin/
    ln_r ${app_prefix}/bin/tmux-mem-cpu-load ${PREFIX}/bin/
}

install_caddy() {
    curl -fsSL -o caddy.tar.gz "$url" && \
    tar zxf caddy.tar.gz -C ${app_prefix} && \
    rm -f caddy.tar.gz && \
    ln_r ${app_prefix}/caddy ${PREFIX}/bin/ && \
    sudo setcap cap_net_bind_service=+ep $(readlink -f $PREFIX/bin/caddy)
}

install_ruby() {
    curl -fsSL "$url" | tar zxf - -C $app_prefix --strip-components=2
    for tool in ruby gem bundle bundler ri rdoc irb; do
        ln_r ${app_prefix}/bin/${tool} ${PREFIX}/bin/
    done

    export PATH="${app_prefix}/bin:$PATH"
    echo >&2 "==> $(command -v ruby)"
    ${app_prefix}/bin/ruby --version 1>&2
    ${app_prefix}/bin/gem install --no-ri --no-rdoc bundler

    prefix_path "${app_prefix}/bin"
}

# shellcheck disable=SC1083,SC2016
install_node() {
    cat > ~/.npmrc << 'EOF'
registry=http://registry.npmjs.org/
prefix=~/.npm-global
EOF
    curl -fsSL "$url" | tar Jxf - -C ${app_prefix} --strip-components=1
    for tool in node npm npx; do
        ln_r ${app_prefix}/bin/${tool} ${PREFIX}/bin/
    done

    prefix_path "${HOME}/.npm-global/bin"
}

[ $# -gt 0 ] || set -- --all

while [ $# -gt 0 ]; do
    cmd="$1"
    shift
    case "$cmd" in
        -f | --force)
            FORCE=true
            ;;
        -d | --directory | --prefix)
            PREFIX="$1"
            shift
            ;;
        --install-*)
            prog="${cmd#--install-}"
            if ! have_app $prog; then
                echo >&2 "==> Installing $prog"
                mkdir -p ${PREFIX}/bin
                app_install ${prog}
            else
                echo >&2 "==> Already have $prog"
            fi
            ;;
        --all)
            mkdir -p ${PREFIX}/bin ${PREFIX}/apps/
            have_app nvim || app_install nvim
            have_app tmux || app_install tmux
            have_app caddy || app_install caddy
            have_app ruby || app_install ruby
            have_app node || app_install node
            ;;
        -h | --help)
            echo >&2
            echo >&2 -n " Usage: $0 [-f|--force] [--all] [-d|--directory|--prefix dir] ["
            grep -Eow '^install_([a-z]+)' $0 | sed -r 's/^install_/--install-/g' | tr '\n' ' ' >&2
            echo >&2 "]"
            echo >&2
            exit 1
            ;;
    esac
done

prefix_path "${PREFIX}/bin"

echo >&2
echo >&2 "Please restart your shell via 'exec \$SHELL -l' or 'source ~/.bashrc'"
echo >&2
