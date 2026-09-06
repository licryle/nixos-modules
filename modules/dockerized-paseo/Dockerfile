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

# 4. Explicit fallback link for pi entrypoint
#RUN ln -sf /usr/local/lib/node_modules/@earendil-works/pi-coding-agent/dist/cli.js /usr/local/bin/pi || true \
#RUN chmod +x /usr/local/bin/pi
#RUN chmod +x /usr/local/bin/gh

#USER paseo