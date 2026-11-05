# Jackal: Pi CLI + Jac, with this repo baked in at /opt/jackal.
# Run with your Jac project mounted at /workspace (see README).

FROM node:22-bookworm-slim

ENV DEBIAN_FRONTEND=noninteractive

ARG JAC_VERSION=0.38.2
ARG JAC_SHA256=c712b056820f67e3035d962a547c7eaea1908a497b63b4b89093fecb9b533ed4

RUN apt-get update \
	&& apt-get install -y --no-install-recommends \
		ca-certificates \
		curl \
		git \
	&& rm -rf /var/lib/apt/lists/*

RUN curl -fsSL \
		-o /usr/local/bin/jac \
		"https://github.com/jaseci-labs/jac/releases/download/v${JAC_VERSION}/jac-${JAC_VERSION}-linux-x86_64" \
	&& echo "${JAC_SHA256}  /usr/local/bin/jac" | sha256sum -c - \
	&& chmod 0755 /usr/local/bin/jac

# Keep in sync with package.json devDependencies / your local `pi --version`
ARG PI_VERSION=0.74.0
RUN npm install -g "@earendil-works/pi-coding-agent@${PI_VERSION}"

COPY . /opt/jackal
WORKDIR /opt/jackal
# Production deps only (matches how the image runs); avoids `npm ci` lockfile strictness for devDependencies.
RUN npm install --omit=dev

ENV JACKAL_AGENT_DIR=/opt/jackal/pi \
	JACKAL_ROOT=/opt/jackal

WORKDIR /workspace
# Native TUI entry (needs a TTY: docker run -t). Headless alternative:
#   jac run /opt/jackal/app/main.jac -- --json
ENTRYPOINT ["jac", "run", "/opt/jackal/app/tui/shell.jac"]
CMD []
