# Jackal: Pi CLI + Jac (for MCP), with this repo baked in at /opt/jackal.
# Run with your Jac project mounted at /workspace (see README).

FROM node:22-bookworm-slim

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update \
	&& apt-get install -y --no-install-recommends \
		python3 \
		python3-pip \
		python3-venv \
		ca-certificates \
		git \
	&& rm -rf /var/lib/apt/lists/*

ENV VIRTUAL_ENV=/opt/jac-venv
RUN python3 -m venv "$VIRTUAL_ENV"
ENV PATH="${VIRTUAL_ENV}/bin:${PATH}"
RUN pip install --no-cache-dir jaclang

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
