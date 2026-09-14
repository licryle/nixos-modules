FROM ghcr.io/getpaseo/paseo:latest

USER root

# Install CLI dependencies (github cli)
# From https://github.com/cli/cli/blob/trunk/docs/install_linux.md#debian
RUN (type -p wget >/dev/null || (apt update && apt install wget -y)) \
	&& mkdir -p -m 755 /etc/apt/keyrings \
	&& out=$(mktemp) && wget -nv -O$out https://cli.github.com/packages/githubcli-archive-keyring.gpg \
	&& cat $out | tee /etc/apt/keyrings/githubcli-archive-keyring.gpg > /dev/null \
	&& chmod go+r /etc/apt/keyrings/githubcli-archive-keyring.gpg \
	&& mkdir -p -m 755 /etc/apt/sources.list.d \
	&& echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | tee /etc/apt/sources.list.d/github-cli.list > /dev/null \
	&& apt update \
	&& apt install gh -y \
  && ln -sf /usr/bin/gh /usr/local/bin/gh \
  && rm -rf /var/lib/apt/lists/*

# 2. Force debconf to default /bin/sh to bash, then reconfigure
#RUN echo "dash dash/sh boolean false" | debconf-set-selections && \
#    dpkg-reconfigure -f noninteractive dash || (rm -f /bin/sh && ln -s /bin/bash /bin/sh)

# 3. Install pi without --ignore-scripts so npm generates the bin link
RUN npm install -g @earendil-works/pi-coding-agent

############ NIX INSTALL ############
# 4. Install Nix-Shell
RUN apt-get update && apt-get install -y curl xz-utils && rm -rf /var/lib/apt/lists/*
RUN mkdir -p /nix && chown -R paseo:paseo /nix

# 5. Drop natively to the paseo user for the installation phase
USER paseo
WORKDIR /home/paseo

# 6. Install Nix without daemon mode AND explicitly pass the sandbox override flag into the installer arguments
RUN mkdir -p /tmp/nix-final-unpack && cd /tmp/nix-final-unpack && \
    curl -LO https://releases.nixos.org/nix/nix-2.35.2/nix-2.35.2-x86_64-linux.tar.xz && \
    tar xf nix-2.35.2-x86_64-linux.tar.xz && \
    cd nix-2.35.2-x86_64-linux && \
    # Crucial: Pre-create the persistent profile directory structure in /nix
    mkdir -p /nix/var/nix/profiles && \
    # Crucial: Redirect the home profile pointer to /nix before the installer runs
    ln -sf /nix/var/nix/profiles/default /home/paseo/.nix-profile && \
    # Set up sandbox configuration
    mkdir -p ~/.config/nix && \
    echo "sandbox = false" > ~/.config/nix/nix.conf && \
    # Run the installer using ONLY valid flags from its menu
    ./install --yes && \
    rm -rf /tmp/nix-final-unpack

# 7. Install direnv using the newly isolated profile system path
RUN /nix/var/nix/profiles/default/bin/nix-env -p /nix/var/nix/profiles/default -iA nixpkgs.direnv

# 8. Switch back to root to inject the global system auto-start hooks
USER root

# Force all runtime instances to bypass container sandboxing locks globally
RUN mkdir -p /etc/nix && echo "sandbox = false" > /etc/nix/nix.conf

# This forces every interactive terminal session to instantly load Nix and Direnv paths
RUN echo '. /nix/var/nix/profiles/default/etc/profile.d/nix.sh' >> /etc/bash.bashrc && \
    echo 'export PATH="/nix/var/nix/profiles/default/bin:${PATH}"' >> /etc/bash.bashrc && \
    echo 'export NIX_PATH="nixpkgs=channel:nixos-unstable"' >> /etc/bash.bashrc && \
    echo 'eval "$(direnv hook bash)"' >> /etc/bash.bashrc

# 9. Set environmental pathways for the remaining build execution layers
ENV PATH="/nix/var/nix/profiles/default/bin:${PATH}" \
    NIX_PATH="nixpkgs=channel:nixos-unstable"

# 10. Test Nix functionality right now during compilation
RUN nix-shell -p coreutils --run "echo 'Nix environment built and saved cleanly!'"

