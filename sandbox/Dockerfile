FROM archlinux:latest
LABEL maintainer "Hamed Mahmoudkhani <ainyava@gmail.com>"

ARG INSTALL_CODE_SERVER="false"


RUN \
  # install packages \
  pacman -Sy --noconfirm gcc-libs tmux ffmpeg zsh git net-tools curl wget neovim python python-pip uv && \
  # ohmyzsh \
  sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"

# vscode server
RUN if [ $INSTALL_CODE_SERVER = "true"]; then \
    curl -fsSL https://code-server.dev/install.sh | sh \
    && code-server --install-extension aaron-bond.better-comments \
    && code-server --install-extension yzhang.markdown-all-in-one \
    && code-server --install-extension naumovs.color-highlight \
    && code-server --install-extension christian-kohler.path-intellisense \
    && code-server --install-extension pkief.material-icon-theme \
    && code-server --install-extension redhat.vscode-yaml \
    && code-server --install-extension ms-python.python \
    && code-server --install-extension charliermarsh.ruff; \
  fi

# configurations
RUN git clone https://github.com/ainyava/dotfiles.git && \
  mkdir -p /root/.config/ && \
  ln -sf ./dotfiles/.config/nvim /root/.config/nvim
