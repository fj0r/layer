FROM fj0rd/scratch:dropbear as dropbear
FROM fj0rd/scratch:dog as dog

FROM fj0rd/0x:php8 as php
RUN set -eux \
  ; mkdir -p /opt/language-server/phpactor \
  ; phpactor_ver=$(curl -sSL https://api.github.com/repos/phpactor/phpactor/releases/latest | jq -r '.tag_name') \
  ; curl -sSL https://github.com/phpactor/phpactor/archive/refs/tags/${phpactor_ver}.tar.gz \
      | tar zxf - -C /opt/language-server/phpactor --strip-components=1 \
  ; cd /opt/language-server/phpactor \
  ; COMPOSER_ALLOW_SUPERUSER=1 composer install \
  ; tar -C /opt/language-server -cf - phpactor | zstd -T0 -19 > /opt/lsphp.tar.zst \
  ;

FROM ubuntu as build

ENV TARGET=/target
ENV NODE_ROOT=/opt/node
ENV NVIM_ROOT=/opt/nvim
ENV NU_ROOT=/opt/nushell
ENV UTILS_ROOT=/opt/utils
ENV LS_ROOT=/opt/language-server
ENV SSHD_ROOT=/opt/dropbear
ENV WASM_ROOT=/opt/wasmtime
ENV PYTHON_ROOT=/opt/python
ENV VSCODE_ROOT=/opt/vscode
ENV PATH=${NODE_ROOT}/bin:${NVIM_ROOT}/bin:$PATH

ENV XDG_CONFIG_HOME=/opt/config

ENV NVIM_PRESET=core \
    PYTHONUNBUFFERED=x


# base
RUN set -eux \
  ; apt update \
  ; apt-get install -y --no-install-recommends \
        curl gnupg ca-certificates \
        zstd xz-utils unzip \
        jq ripgrep git build-essential \
  ; apt-get autoremove -y && apt-get clean -y && rm -rf /var/lib/apt/lists/* \
  \
  ; mkdir -p ${TARGET} \
  ; mkdir -p $NVIM_ROOT \
  ; mkdir -p $NODE_ROOT \
  ; mkdir -p $UTILS_ROOT \
  ; mkdir -p $LS_ROOT \
  ; mkdir -p $NU_ROOT \
  ; mkdir -p $SSHD_ROOT \
  ; mkdir -p $WASM_ROOT \
  ; mkdir -p $PYTHON_ROOT \
  ; mkdir -p $VSCODE_ROOT \
  ;

# wasmtime
RUN set -eux \
  ; wasmtime_ver=$(curl -sSL https://api.github.com/repos/bytecodealliance/wasmtime/releases/latest | jq -r '.tag_name') \
  ; wasmtime_url="https://github.com/bytecodealliance/wasmtime/releases/latest/download/wasmtime-${wasmtime_ver}-x86_64-linux.tar.xz" \
  ; curl -sSL ${wasmtime_url} | tar Jxf - --strip-components=1 -C $WASM_ROOT --wildcards '*/wasmtime' \
  ; find $WASM_ROOT -type f -exec grep -IL . "{}" \; | xargs -L 1 strip \
  ; tar -C $(dirname $WASM_ROOT) -cf - $(basename $WASM_ROOT) | zstd -T0 -19 > $TARGET/wasmtime.tar.zst \
  ;

# node
RUN set -eux \
  ; node_version=$(curl -sSL https://nodejs.org/en/download/ | rg 'Latest LTS Version.*<strong>(.+)</strong>' -or '$1') \
  ; curl -sSL https://nodejs.org/dist/v${node_version}/node-v${node_version}-linux-x64.tar.xz \
    | tar Jxf - --strip-components=1 -C $NODE_ROOT \
  \
  # lspy lsyaml lsjson
  ; npm install --location=global \
        quicktype \
        pyright \
        vscode-langservers-extracted \
        yaml-language-server \
  ; npm cache clean -f \
  ; tar -C $(dirname $NODE_ROOT) -cf - $(basename $NODE_ROOT)| zstd -T0 -19 > $TARGET/node.tar.zst \
  \
  # lslua
  ; lslua_ver=$(curl -sSL https://api.github.com/repos/sumneko/lua-language-server/releases/latest | jq -r '.tag_name') \
  ; lslua_url="https://github.com/sumneko/lua-language-server/releases/latest/download/lua-language-server-${lslua_ver}-linux-x64.tar.gz" \
  ; mkdir -p $LS_ROOT/sumneko_lua \
  ; curl -sSL ${lslua_url} | tar zxf - \
      -C $LS_ROOT/sumneko_lua \
  ; tar -C $LS_ROOT -cf - sumneko_lua | zstd -T0 -19 > $TARGET/lslua.tar.zst \
  \
  # lsnode
  ; git clone --depth=1 https://github.com/microsoft/vscode-node-debug2.git $LS_ROOT/vscode-node-debug2 \
  ; cd $LS_ROOT/vscode-node-debug2 \
  ; npm install \
  ; NODE_OPTIONS=--no-experimental-fetch npm run build \
  ; tar -C $LS_ROOT -cf - vscode-node-debug2 | zstd -T0 -19 > $TARGET/lsnode.tar.zst \
  ;

# php
COPY --from=php /opt/lsphp.tar.zst $TARGET
RUN set -eux \
  ; git clone --depth=1 https://github.com/xdebug/vscode-php-debug.git $LS_ROOT/vscode-php-debug \
  ; cd $LS_ROOT/vscode-php-debug \
  ; npm install && npm run build \
  ; tar -C $LS_ROOT -cf - vscode-php-debug | zstd -T0 -19 > $TARGET/phpdb.tar.zst \
  ;

# nushell
RUN set -eux \
  ; zoxide_ver=$(curl -sSL https://api.github.com/repos/ajeetdsouza/zoxide/releases/latest | jq -r '.tag_name' | cut -c 2-) \
  ; zoxide_url="https://github.com/ajeetdsouza/zoxide/releases/latest/download/zoxide-${zoxide_ver}-x86_64-unknown-linux-musl.tar.gz" \
  ; curl -sSL ${zoxide_url} | tar zxf - -C $NU_ROOT zoxide \
  \
  ; nu_ver=$(curl -sSL https://api.github.com/repos/nushell/nushell/releases/latest | jq -r '.tag_name') \
  ; nu_url="https://github.com/nushell/nushell/releases/latest/download/nu-${nu_ver}-x86_64-unknown-linux-musl.tar.gz" \
  ; curl -sSL ${nu_url} | tar zxf - -C $NU_ROOT --strip-components=1 --wildcards '*/nu' \
  ; tar -C $(dirname $NU_ROOT) -cf - $(basename $NU_ROOT) | zstd -T0 -19 > $TARGET/nushell.tar.zst \
  ; git clone --depth=1 https://github.com/fj0r/nushell.git ${HOME}/.config/nushell \
  ; tar -C ${HOME}/.config -cf - nushell | zstd -T0 -19 > $TARGET/nushell.conf.tar.zst \
  ;

# utils
COPY --from=dog /usr/local/bin/dog $UTILS_ROOT/dog
RUN set -eux \
  ; rg_ver=$(curl -sSL https://api.github.com/repos/BurntSushi/ripgrep/releases/latest | jq -r '.tag_name') \
  ; rg_url="https://github.com/BurntSushi/ripgrep/releases/latest/download/ripgrep-${rg_ver}-x86_64-unknown-linux-musl.tar.gz" \
  ; curl -sSL ${rg_url} | tar zxf - -C $UTILS_ROOT --strip-components=1 --wildcards '*/rg' \
  \
  ; echo "download yq in $(pwd)" \
  ; yq_url="https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64.tar.gz" \
  ; curl -sSL ${yq_url} | tar zxf - && mv yq_linux_amd64 $UTILS_ROOT/yq \
  \
  ; fd_ver=$(curl -sSL https://api.github.com/repos/sharkdp/fd/releases/latest | jq -r '.tag_name') \
  ; fd_url="https://github.com/sharkdp/fd/releases/latest/download/fd-${fd_ver}-x86_64-unknown-linux-musl.tar.gz" \
  ; curl -sSL ${fd_url} | tar zxf - -C $UTILS_ROOT --strip-components=1 --wildcards '*/fd' \
  \
  ; sd_ver=$(curl -sSL https://api.github.com/repos/chmln/sd/releases/latest | jq -r '.tag_name') \
  ; echo "download sd ${sd_ver} in $(pwd)" \
  ; sd_url="https://github.com/chmln/sd/releases/latest/download/sd-${sd_ver}-x86_64-unknown-linux-musl" \
  ; curl -sSL ${sd_url} -o $UTILS_ROOT/sd && chmod +x $UTILS_ROOT/sd \
  \
  ; just_ver=$(curl -sSL https://api.github.com/repos/casey/just/releases/latest | jq -r '.tag_name') \
  ; just_url="https://github.com/casey/just/releases/latest/download/just-${just_ver}-x86_64-unknown-linux-musl.tar.gz" \
  ; curl -sSL ${just_url} | tar zxf - -C $UTILS_ROOT just \
  \
  ; watchexec_ver=$(curl -sSL https://api.github.com/repos/watchexec/watchexec/releases/latest  | jq -r '.tag_name' | cut -c 2-) \
  ; watchexec_url="https://github.com/watchexec/watchexec/releases/latest/download/watchexec-${watchexec_ver}-x86_64-unknown-linux-gnu.tar.xz" \
  ; curl -sSL ${watchexec_url} | tar Jxf - --strip-components=1 -C $UTILS_ROOT --wildcards '*/watchexec' \
  \
  ; btm_url="https://github.com/ClementTsang/bottom/releases/latest/download/bottom_x86_64-unknown-linux-musl.tar.gz" \
  ; curl -sSL ${btm_url} | tar zxf - -C $UTILS_ROOT btm \
  \
  ; dust_ver=$(curl -sSL https://api.github.com/repos/bootandy/dust/releases/latest | jq -r '.tag_name') \
  ; dust_url="https://github.com/bootandy/dust/releases/latest/download/dust-${dust_ver}-x86_64-unknown-linux-musl.tar.gz" \
  ; curl -sSL ${dust_url} | tar zxf - -C $UTILS_ROOT --strip-components=1 --wildcards '*/dust' \
  \
  ; find $UTILS_ROOT -type f -exec grep -IL . "{}" \; | xargs -L 1 strip -s \
  ; tar -C $(dirname $UTILS_ROOT) -cf - $(basename $UTILS_ROOT) | zstd -T0 -19 > $TARGET/utils.tar.zst \
  ;

# nvim
RUN set -eux \
  #; nvim_url=$(curl -sSL https://api.github.com/repos/neovim/neovim/releases -H 'Accept: application/vnd.github.v3+json' \
  #           | jq -r '[.[]|select(.prerelease==false)][0].assets[].browser_download_url' | grep -v sha256sum | grep linux64.tar.gz) \
  ; nvim_url=https://github.com/neovim/neovim/releases/latest/download/nvim-linux64.tar.gz \
  ; curl -sSL ${nvim_url} | tar zxf - -C $NVIM_ROOT --strip-components=1 \
  \
  ; rg_ver=$(curl -sSL https://api.github.com/repos/BurntSushi/ripgrep/releases/latest | jq -r '.tag_name') \
  ; rg_url="https://github.com/BurntSushi/ripgrep/releases/latest/download/ripgrep-${rg_ver}-x86_64-unknown-linux-musl.tar.gz" \
  ; curl -sSL ${rg_url} | tar zxf - -C $NVIM_ROOT/bin --strip-components=1 --wildcards '*/rg' \
  \
  ; tar -C $(dirname $NVIM_ROOT) -cf - $(basename $NVIM_ROOT) | zstd -T0 -19 > $TARGET/nvim.tar.zst \
  \
  ; mkdir -p ${XDG_CONFIG_HOME} \
  ; git clone --depth=1 https://github.com/fj0r/nvim-lua.git $XDG_CONFIG_HOME/nvim \
  ; nvim --headless "+Lazy! sync" +qa \
  \
  ; tsl=$(cat $XDG_CONFIG_HOME/nvim/lua/lang/treesitter_lang.json|jq -r 'join(" ")') \
  ; nvim --headless -c "TSUpdateSync ${tsl}" -c 'quit' \
  ; rm -rf $XDG_CONFIG_HOME/nvim/pack/packer/*/*/.git \
  ; tar -C ${XDG_CONFIG_HOME} -cf - nvim | zstd -T0 -19 > $TARGET/nvim.conf.tar.zst

# python
ARG PYTHON_VERSION=3.10
RUN set -eux \
  ; py_url=$(curl -sSL https://api.github.com/repos/indygreg/python-build-standalone/releases/latest \
          | jq -r '.assets[].browser_download_url' \
          | grep -v sha256 \
          | grep x86_64-unknown-linux-musl-install_only \
          | grep ${PYTHON_VERSION} \
          )\
  ; curl -sSL ${py_url} | tar zxf - -C ${PYTHON_ROOT} --strip-components=1 \
  ; ${PYTHON_ROOT}/bin/pip3 --no-cache-dir install debugpy \
  ; tar -C $(dirname $PYTHON_ROOT) -cf - $(basename $PYTHON_ROOT) | zstd -T0 -19 > $TARGET/python.tar.zst

# sshd
COPY --from=dropbear / $SSHD_ROOT
RUN set -eux \
  ; tar -C $(dirname $SSHD_ROOT) -cf - $(basename $SSHD_ROOT) | zstd -T0 -19 > $TARGET/sshd.tar.zst \
  ;

# mutagen
RUN set -eux \
  ; mkdir -p /opt/mutagen \
  ; cd /opt/mutagen \
  ; mutagen_ver=$(curl -sSL https://api.github.com/repos/mutagen-io/mutagen/releases/latest | jq -r '.tag_name') \
  ; curl -sSL https://github.com/mutagen-io/mutagen/releases/download/${mutagen_ver}/mutagen_windows_amd64_${mutagen_ver}.tar.gz | tar -zxf - -C /opt/mutagen \
  ; rm -f mutagen-agents.tar.gz \
  ; curl -sSL https://github.com/mutagen-io/mutagen/releases/download/${mutagen_ver}/mutagen_linux_amd64_${mutagen_ver}.tar.gz | tar -zxf - -C /opt/mutagen \
  ; mkdir mutagen-agents \
  ; tar zxvf mutagen-agents.tar.gz -C mutagen-agents \
  ; rm -f mutagen-agents.tar.gz \
  ; tar zcvf mutagen-agents.tar.gz -C mutagen-agents \
        linux_386 linux_amd64 linux_arm linux_arm64 \
        windows_386 windows_amd64 darwin_amd64 freebsd_amd64 \
  ; rm -rf mutagen-agents \
  ; tar -C /opt -cf - mutagen | zstd -T0 -19 > $TARGET/mutagen.tar.zst \
  ;

# kubectl
RUN set -eux \
  ; mkdir -p /opt/kubectl \
  ; k8s_ver=$(curl -s https://storage.googleapis.com/kubernetes-release/release/stable.txt | cut -c 2-) \
  ; k8s_url="https://dl.k8s.io/v${k8s_ver}/kubernetes-client-linux-amd64.tar.gz" \
  ; curl -L ${k8s_url} | tar zxf - --strip-components=3 -C /opt/kubectl kubernetes/client/bin/kubectl \
  ; chmod +x /opt/kubectl/kubectl \
  ; tar -C /opt -cf - kubectl | zstd -T0 -19 > $TARGET/kubectl.tar.zst \
  ;

# vscode-server
RUN set -eux \
  ; commit_id=$(curl -sSL https://github.com/microsoft/vscode/tags \
    | rg '<a.*href="/microsoft/vscode/commit/(.+)">' -or '$1' | head -n 1) \
  ; mkdir -p $VSCODE_ROOT/vscode-server/bin/${commit_id} \
  ; curl -sSL "https://update.code.visualstudio.com/commit:${commit_id}/server-linux-x64/stable" \
    | tar -zxf - -C $VSCODE_ROOT/vscode-server/bin/${commit_id} --strip-components=1 \
  ; tar -C $VSCODE_ROOT -cf - vscode-server | zstd -T0 -19 > $TARGET/vscode-server.tar.zst \
  ;


#------
FROM fj0rd/0x:latest as openresty
RUN set -eux \
  ; mkdir -p /target \
  ; tar -C /opt -cf - openresty | zstd -T0 -19 > /target/openresty.tar.zst

FROM fj0rd/0x:or
COPY --from=build /target /srv
COPY --from=openresty /target /srv
COPY nginx.conf /etc/openresty/nginx.conf
#COPY setup.sh /srv
COPY setup.py /
COPY setup.yaml /
RUN set -eux \
  ; ln -sf /usr/share/zoneinfo/$TIMEZONE /etc/localtime \
  ; echo "$TIMEZONE" > /etc/timezone \
  ; apk add --no-cache python3 py3-pip \
  ; pip3 --no-cache-dir install pyyaml pystache \
  ; echo '{}' | jq '.build="'$(date -Is)'"' > /about.json

