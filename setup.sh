#!/bin/sh

HOST=${HTTP_HOST}


fetch () {
    mkdir -p $2
    curl -sSL ${HOST}/$1.tar.zst | zstd -d -T0 | tar -xf - -C $2 --strip-components=1
}

setup_nushell () {
    echo --- setup nushell
    fetch nushell /usr/local
    fetch nushell.conf ${HOME}/.config/nushell
    echo --- done
}

setup_nvim() {
    echo --- setup nvim
    fetch nvim /usr/local
    fetch nvim.conf ${HOME}/.config/nvim
    echo --- done
}

setup_openresty() {
    echo --- setup openresty
    fetch openresty /opt/openresty
    echo --- done
}

setup_node() {
    echo --- setup node, lspy, lsyaml, lsjson
    fetch node /usr/local
    echo --- done
}

setup_python() {
    echo --- setup python
    fetch python /opt/python
    echo --- done
}

setup_lsphp() {
    echo --- setup lsphp
    fetch lsphp /opt/language-server/vscode-php-debug
    echo --- done
}

setup_lsnode() {
    echo --- setup lsnode
    fetch lsnode /opt/language-server/vscode-node-debug2
    echo --- done
}

setup_lslua() {
    echo --- setup lslua
    fetch lslua /opt/language-server/sumneko_lua
    echo --- done
}

for i in "$@"; do
    eval "setup_$i"
done
