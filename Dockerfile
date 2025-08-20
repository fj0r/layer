FROM ghcr.io/fj0r/io:__dropbear__ AS dropbear

FROM ghcr.io/fj0r/0x:php8 AS php
ENV LS_ROOT=/opt/language-server
RUN set -eux \
  ; mkdir -p ${LS_ROOT}/phpactor \
  ; phpactor_ver=$(curl --retry 3 -sSL https://api.github.com/repos/phpactor/phpactor/releases/latest | jq -r '.tag_name') \
  ; curl --retry 3 -sSL https://github.com/phpactor/phpactor/archive/refs/tags/${phpactor_ver}.tar.gz \
      | tar zxf - -C ${LS_ROOT}/phpactor --strip-components=1 \
  ; cd ${LS_ROOT}/phpactor \
  ; COMPOSER_ALLOW_SUPERUSER=1 composer install \
  ; tar -C ${LS_ROOT} -cf - phpactor | zstd -T0 -19 > /opt/lsphp.tar.zst \
  ;

FROM debian:bookworm-slim AS build

ENV TARGET=/target
ENV NODE_ROOT=/opt/node
ENV NVIM_ROOT=/opt/nvim
#ENV NVIM_MUSL=1
ENV NU_ROOT=/opt/nushell
ENV ZJ_ROOT=/opt/zellij
ENV UTILS_ROOT=/opt/utils
ENV LS_ROOT=/opt/language-server
ENV SSHD_ROOT=/opt/dropbear
ENV WASM_ROOT=/opt/wasmtime
ENV SPIN_ROOT=/opt/spin
ENV PYTHON_ROOT=/opt/python
ENV VSCODE_ROOT=/opt/vscode
ENV PATH=${NODE_ROOT}/bin:${NVIM_ROOT}/bin:$PATH

ENV XDG_CONFIG_HOME=/opt/config

ENV PYTHONUNBUFFERED=x


# base
RUN set -eux \
  ; apt update \
  ; apt-get install -y --no-install-recommends \
        curl gnupg ca-certificates \
        zstd xz-utils unzip tree \
        jq ripgrep git build-essential cmake \
        musl-dev musl-tools \
  ; ln -s /usr/bin/g++ /usr/bin/musl-g++ \
  ; apt-get autoremove -y \
  ; apt-get clean -y \
  ; rm -rf /var/lib/apt/lists/* \
  \
  ; mkdir -p ${TARGET} \
  ; mkdir -p $NVIM_ROOT \
  ; mkdir -p $NODE_ROOT \
  ; mkdir -p $UTILS_ROOT \
  ; mkdir -p $LS_ROOT \
  ; mkdir -p $NU_ROOT \
  ; mkdir -p $ZJ_ROOT \
  ; mkdir -p $SSHD_ROOT \
  ; mkdir -p $WASM_ROOT \
  ; mkdir -p $SPIN_ROOT \
  ; mkdir -p $PYTHON_ROOT \
  ; mkdir -p $VSCODE_ROOT \
  ;

# python
ARG PYTHON_VERSION=3.13
ARG COMMITMSG
RUN set -x \
  ; py_build=$(curl --retry 3 -sSL https://api.github.com/repos/indygreg/python-build-standalone/releases | jq -r '[.[]|select(.prerelease == false)][0].tag_name') \
  ; py_buildmsg=$(echo "${COMMITMSG}" | rg 'py_build=([^\s]+)' -or '$1') \
  ; py_build=${py_buildmsg:-${py_build}} \
  ; py_url=$(curl --retry 3 -sSL https://api.github.com/repos/indygreg/python-build-standalone/releases/tags/${py_build} \
          | jq -r '.assets[].browser_download_url' \
          | grep -v sha256 \
          | grep x86_64-unknown-linux-musl-install_only \
          | grep -F ${PYTHON_VERSION} \
          )\
  ; curl --retry 3 -sSL ${py_url} | tar zxf - -C ${PYTHON_ROOT} --strip-components=1 \
  #; CC="/opt/musl/bin/x86_64-linux-musl-gcc -fPIE -pie" \
  #; ${PYTHON_ROOT}/bin/pip3 install --no-cache-dir --use-pep517 debugpy \
  ; ${PYTHON_ROOT}/bin/pip3 install --no-cache-dir debugpy \
  ; tar -C $(dirname $PYTHON_ROOT) -cf - $(basename $PYTHON_ROOT) | zstd -T0 -19 > $TARGET/python.tar.zst

# wasmtime
RUN set -eux \
  ; wasmtime_ver=$(curl --retry 3 -sSL https://api.github.com/repos/bytecodealliance/wasmtime/releases/latest | jq -r '.tag_name') \
  ; wasmtime_url="https://github.com/bytecodealliance/wasmtime/releases/latest/download/wasmtime-${wasmtime_ver}-x86_64-linux.tar.xz" \
  ; curl --retry 3 -sSL ${wasmtime_url} | tar Jxf - --strip-components=1 -C $WASM_ROOT --wildcards '*/wasmtime' \
  ; find $WASM_ROOT -type f -exec grep -IL . "{}" \; | xargs -L 1 strip \
  ; tar -C $(dirname $WASM_ROOT) -cf - $(basename $WASM_ROOT) | zstd -T0 -19 > $TARGET/wasmtime.tar.zst \
  ;

# spin
RUN set -eux \
  ; spin_ver=$(curl --retry 3 -sSL https://api.github.com/repos/fermyon/spin/releases/latest | jq -r '.tag_name') \
  ; spin_url="https://github.com/fermyon/spin/releases/download/${spin_ver}/spin-${spin_ver}-linux-amd64.tar.gz" \
  ; curl --retry 3 -sSL ${spin_url} | tar zxf - -C $SPIN_ROOT spin \
  ; find $SPIN_ROOT -type f -exec grep -IL . "{}" \; | xargs -L 1 strip \
  ; tar -C $(dirname $SPIN_ROOT) -cf - $(basename $SPIN_ROOT) | zstd -T0 -19 > $TARGET/spin.tar.zst \
  ;

# node
RUN set -eux \
  ; node_version=$(curl --retry 3 -sSL https://nodejs.org/dist/index.json | jq -r '[.[]|select(.lts != false)][0].version') \
  ; curl --retry 3 -sSL https://nodejs.org/dist/${node_version}/node-${node_version}-linux-x64.tar.xz \
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
  ; lslua_ver=$(curl --retry 3 -sSL https://api.github.com/repos/LuaLS/lua-language-server/releases/latest | jq -r '.tag_name') \
  ; lslua_url="https://github.com/LuaLS/lua-language-server/releases/latest/download/lua-language-server-${lslua_ver}-linux-x64.tar.gz" \
  ; mkdir -p $LS_ROOT/lua-language-server \
  ; curl --retry 3 -sSL ${lslua_url} | tar zxf - -C $LS_ROOT/lua-language-server \
  ; tar -C $LS_ROOT -cf - lua-language-server | zstd -T0 -19 > $TARGET/lslua.tar.zst \
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
  ; npm install \
  ; npm run build \
  ; tar -C $LS_ROOT -cf - vscode-php-debug | zstd -T0 -19 > $TARGET/phpdb.tar.zst \
  ;

# nushell
RUN set -eux \
  ; nu_ver=$(curl --retry 3 -sSL https://api.github.com/repos/nushell/nushell/releases/latest | jq -r '.tag_name') \
  ; nu_url="https://github.com/nushell/nushell/releases/download/${nu_ver}/nu-${nu_ver}-x86_64-unknown-linux-musl.tar.gz" \
  ; curl --retry 3 -sSL ${nu_url} | tar zxf - -C $NU_ROOT --strip-components=1 --wildcards '*/nu' '*/nu_plugin_query' \
  ; tar -C $(dirname $NU_ROOT) -cf - $(basename $NU_ROOT) | zstd -T0 -19 > $TARGET/nushell.tar.zst \
  ; git clone --depth=3 https://github.com/fj0r/nushell.git ${HOME}/.config/nushell \
  ; opwd=$PWD; cd ${HOME}/.config/nushell; git log -1 --date=iso; cd $opwd \
  ; tar -C ${HOME}/.config -cf - nushell | zstd -T0 -19 > $TARGET/nushell.conf.tar.zst \
  ;

# zellij
RUN set -eux \
  ; zj_ver=$(curl --retry 3 -sSL https://api.github.com/repos/zellij-org/zellij/releases/latest | jq -r '.tag_name') \
  ; zj_url="https://github.com/zellij-org/zellij/releases/download/${zj_ver}/zellij-x86_64-unknown-linux-musl.tar.gz" \
  ; curl --retry 3 -sSL ${zj_url} | tar zxf - -C $ZJ_ROOT \
  ; tar -C $(dirname $ZJ_ROOT) -cf - $(basename $ZJ_ROOT) | zstd -T0 -19 > $TARGET/zellij.tar.zst \
  ; git clone --depth=3 https://github.com/fj0r/zellij.git ${HOME}/.config/zellij \
  ; opwd=$PWD; cd ${HOME}/.config/zellij; git log -1 --date=iso; cd $opwd \
  ; tar -C ${HOME}/.config -cf - zellij | zstd -T0 -19 > $TARGET/zellij.conf.tar.zst \
  ;

# utils
RUN set -eux \
  ; rg_ver=$(curl --retry 3 -sSL https://api.github.com/repos/BurntSushi/ripgrep/releases/latest | jq -r '.tag_name') \
  ; rg_url="https://github.com/BurntSushi/ripgrep/releases/latest/download/ripgrep-${rg_ver}-x86_64-unknown-linux-musl.tar.gz" \
  ; curl --retry 3 -sSL ${rg_url} | tar zxf - -C $UTILS_ROOT --strip-components=1 --wildcards '*/rg' \
  \
  ; fd_ver=$(curl --retry 3 -sSL https://api.github.com/repos/sharkdp/fd/releases/latest | jq -r '.tag_name') \
  ; fd_url="https://github.com/sharkdp/fd/releases/latest/download/fd-${fd_ver}-x86_64-unknown-linux-musl.tar.gz" \
  ; curl --retry 3 -sSL ${fd_url} | tar zxf - -C $UTILS_ROOT --strip-components=1 --wildcards '*/fd' \
  \
  ; echo "download yq in $(pwd)" \
  ; yq_url="https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64.tar.gz" \
  ; curl --retry 3 -sSL ${yq_url} | tar zxf - ./yq_linux_amd64 \
  ; mv yq_linux_amd64 $UTILS_ROOT/yq \
  \
  ; btm_url="https://github.com/ClementTsang/bottom/releases/latest/download/bottom_x86_64-unknown-linux-musl.tar.gz" \
  ; curl --retry 3 -sSL ${btm_url} | tar zxf - -C $UTILS_ROOT btm \
  \
  ; dua_ver=$(curl --retry 3 -fsSL https://api.github.com/repos/Byron/dua-cli/releases/latest | jq -r '.tag_name') \
  ; dua_url="https://github.com/Byron/dua-cli/releases/download/${dua_ver}/dua-${dua_ver}-x86_64-unknown-linux-musl.tar.gz" \
  ; curl --retry 3 -fsSL ${dua_url} | tar zxf - -C $UTILS_ROOT --strip-components=1 --wildcards '*/dua' \
  \
  ; bdwh_ver=$(curl --retry 3 -sSL https://api.github.com/repos/imsnif/bandwhich/releases/latest | jq -r '.tag_name') \
  ; bdwh_url="https://github.com/imsnif/bandwhich/releases/download/${bdwh_ver}/bandwhich-${bdwh_ver}-x86_64-unknown-linux-musl.tar.gz" \
  ; curl --retry 3 -sSL ${bdwh_url} | tar zxf - -C $UTILS_ROOT \
  \
  ; find $UTILS_ROOT -type f -exec grep -IL . "{}" \; | xargs -L 1 strip -s \
  ; tar -C $(dirname $UTILS_ROOT) -cf - $(basename $UTILS_ROOT) | zstd -T0 -19 > $TARGET/utils.tar.zst \
  ;

# nvim
RUN set -eux \
  #; nvim_url=$(curl --retry 3 -sSL https://api.github.com/repos/neovim/neovim/releases -H 'Accept: application/vnd.github.v3+json' \
  #           | jq -r '[.[]|select(.prerelease==false)][0].assets[].browser_download_url' | grep -v sha256sum | grep linux64.tar.gz) \
  ; nvim_ver=$(curl --retry 3 -sSL https://api.github.com/repos/neovim/neovim/releases/latest | jq -r '.tag_name') \
  ; nvim_url="https://github.com/neovim/neovim/releases/download/${nvim_ver}/nvim-linux-x86_64.tar.gz" \
  ; curl --retry 3 -sSL ${nvim_url} | tar zxf - -C $NVIM_ROOT --strip-components=1 \
  \
  ; rg_ver=$(curl --retry 3 -sSL https://api.github.com/repos/BurntSushi/ripgrep/releases/latest | jq -r '.tag_name') \
  ; rg_url="https://github.com/BurntSushi/ripgrep/releases/latest/download/ripgrep-${rg_ver}-x86_64-unknown-linux-musl.tar.gz" \
  ; curl --retry 3 -sSL ${rg_url} | tar zxf - -C $NVIM_ROOT/bin --strip-components=1 --wildcards '*/rg' \
  \
  ; fd_ver=$(curl --retry 3 -sSL https://api.github.com/repos/sharkdp/fd/releases/latest | jq -r '.tag_name') \
  ; fd_url="https://github.com/sharkdp/fd/releases/latest/download/fd-${fd_ver}-x86_64-unknown-linux-musl.tar.gz" \
  ; curl --retry 3 -sSL ${fd_url} | tar zxf - -C /usr/local/bin --strip-components=1 --wildcards '*/fd' \
  \
  ; tar -C $(dirname $NVIM_ROOT) -cf - $(basename $NVIM_ROOT) | zstd -T0 -19 > $TARGET/nvim.tar.zst \
  \
  ; mkdir -p ${XDG_CONFIG_HOME} \
  ; git clone --depth=1 https://github.com/fj0r/nvim-lua.git $XDG_CONFIG_HOME/nvim \
  ; opwd=$PWD; cd $XDG_CONFIG_HOME/nvim; git log -1 --date=iso; cd $opwd \
  ; nvim --headless "+Lazy! sync" +qa \
  #; nvim --headless "+Lazy! build telescope-fzf-native.nvim" +qa \
  \
  ; rm -rf $XDG_CONFIG_HOME/nvim/lazy/packages/*/.git \
  ; tar -C ${XDG_CONFIG_HOME} -cf - nvim | zstd -T0 -19 > $TARGET/nvim.conf.tar.zst

# sshd
COPY --from=dropbear / $SSHD_ROOT
RUN set -eux \
  ; tar -C $(dirname $SSHD_ROOT) -cf - $(basename $SSHD_ROOT) | zstd -T0 -19 > $TARGET/sshd.tar.zst \
  ;

# mutagen
RUN set -eux \
  ; mkdir -p /opt/mutagen \
  ; cd /opt/mutagen \
  ; mutagen_ver=$(curl --retry 3 -sSL https://api.github.com/repos/mutagen-io/mutagen/releases/latest | jq -r '.tag_name') \
  ; curl --retry 3 -sSL https://github.com/mutagen-io/mutagen/releases/download/${mutagen_ver}/mutagen_windows_amd64_${mutagen_ver}.tar.gz | tar -zxf - -C /opt/mutagen \
  ; rm -f mutagen-agents.tar.gz \
  ; curl --retry 3 -sSL https://github.com/mutagen-io/mutagen/releases/download/${mutagen_ver}/mutagen_linux_arm64_${mutagen_ver}.tar.gz | tar -zxf - -C /opt/mutagen \
  ; rm -f mutagen-agents.tar.gz \
  ; curl --retry 3 -sSL https://github.com/mutagen-io/mutagen/releases/download/${mutagen_ver}/mutagen_linux_amd64_${mutagen_ver}.tar.gz | tar -zxf - -C /opt/mutagen \
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
  ; k8s_ver=$(curl --retry 3 -s https://storage.googleapis.com/kubernetes-release/release/stable.txt | cut -c 2-) \
  ; k8s_url="https://dl.k8s.io/v${k8s_ver}/kubernetes-client-linux-amd64.tar.gz" \
  ; curl --retry 3 -L ${k8s_url} | tar -zxf - --strip-components=3 -C /opt/kubectl kubernetes/client/bin/kubectl \
  ; chmod +x /opt/kubectl/kubectl \
  \
  ; helm_ver=$(curl --retry 3 -sSL https://api.github.com/repos/helm/helm/releases/latest | jq -r '.tag_name' | cut -c 2-) \
  ; curl --retry 3 -L https://get.helm.sh/helm-v${helm_ver}-linux-amd64.tar.gz \
      | tar zxvf - -C /opt/kubectl linux-amd64/helm --strip-components=1 \
  \
  ; tar -C /opt -cf - kubectl | zstd -T0 -19 > $TARGET/kubectl.tar.zst \
  ;

# vector
RUN set -eux \
  ; mkdir -p /opt/vector \
  ; vector_ver=$(curl --retry 3 -sSL https://api.github.com/repos/vectordotdev/vector/releases/latest | jq -r '.tag_name' | cut -c 2-) \
  ; vector_url="https://github.com/vectordotdev/vector/releases/latest/download/vector-${vector_ver}-x86_64-unknown-linux-musl.tar.gz" \
  ; curl --retry 3 -sSL ${vector_url} | tar -zxf - -C /opt/vector --strip-components=3 ./vector-x86_64-unknown-linux-musl/bin/vector \
  ; chmod +x /opt/vector/vector \
  ; tar -C /opt -cf - vector | zstd -T0 -19 > $TARGET/vector.tar.zst \
  ;

# code-server
# COPY code/code.sh /opt/code-server/code.sh
# COPY code/settings.json /opt/code-server/user-data/Machine/settings.json
# RUN set -eux \
#   ; mkdir -p /opt/code-server/extensions \
#   ; mkdir -p /opt/code-server/user-data \
#   ; code_ver=$(curl --retry 3 -sSL https://api.github.com/repos/coder/code-server/releases/latest | jq -r '.tag_name' | cut -c 2-) \
#   ; code_url="https://github.com/coder/code-server/releases/download/v${code_ver}/code-server-${code_ver}-linux-amd64.tar.gz" \
#   ; curl --retry 3 -sSL ${code_url} | tar zxf - --strip-components=1 -C /opt/code-server \
#   \
#   ; for i in \
#         # asvetliakov.vscode-neovim \
#         # vscodevim.vim \
#         ms-python.python \
#         ms-toolsai.jupyter \
#         redhat.vscode-yaml \
#         rust-lang.rust \
#         bungcip.better-toml \
#         serayuzgur.crates \
#         Swellaby.vscode-rust-test-adapter \
#         haskell.haskell \
#         golang.Go \
#         julialang.language-julia \
#         Vue.volar \
#         devsense.phptools-vscode \
#   ; do \
#         /opt/code-server/bin/code-server \
#             --extensions-dir /opt/code-server/extensions \
#             --user-data-dir /opt/code-server/user-data \
#             --install-extension $i \
#   ; done \
#   ; rm -rf /opt/code-server/user-data \
#   ; mkdir -p /opt/code-server/user-data/Machine \
#   ; mkdir -p /opt/code-server/user-data/User \
#   ; tar -C /opt -cf - code-server | zstd -T0 -19 > $TARGET/code-server.tar.zst \
#   ;


#------
FROM ghcr.io/fj0r/scratch:zstd AS zstd
FROM ghcr.io/fj0r/0x:openresty AS openresty
RUN set -eux \
  ; mkdir -p /target \
  ; tar -C /usr/local -cf - openresty | zstd -T0 -19 > /target/openresty.tar.zst

FROM ghcr.io/fj0r/0x:or
COPY --from=zstd /usr/local/bin/zstd /srv
COPY --from=build /target /srv
COPY --from=openresty /target /srv
COPY setup.nginx.conf /etc/openresty/ext/setup.conf
COPY app /app
RUN set -eux \
  ; ln -sf /usr/share/zoneinfo/$TIMEZONE /etc/localtime \
  ; echo "$TIMEZONE" > /etc/timezone \
  ; apk add --no-cache python3 py3-pip \
  ; pip3 install --break-system-packages --no-cache-dir pyyaml pystache \
  ; echo '{}' | jq '.build="'$(date -Is)'"' > /about.json

