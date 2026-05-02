FROM ghcr.io/ggml-org/llama.cpp:server-cuda

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

ENV DEBIAN_FRONTEND=noninteractive \
    OPENWEBUI_VENV=/opt/openwebui-venv \
    MODEL_DIR=/tmp/models \
    HF_HOME=/tmp/hf_home \
    DATA_DIR=/tmp/open-webui-data \
    PATH="/opt/openwebui-venv/bin:/root/.local/bin:${PATH}"

USER root

RUN apt-get update && apt-get install -y --no-install-recommends \
      bash \
      ca-certificates \
      curl \
      git \
      procps \
      tini \
    && rm -rf /var/lib/apt/lists/*

RUN curl -LsSf https://astral.sh/uv/install.sh | sh \
    && /root/.local/bin/uv venv --python 3.11 "${OPENWEBUI_VENV}" \
    && "${OPENWEBUI_VENV}/bin/python" -m pip install --upgrade pip wheel setuptools \
    && "${OPENWEBUI_VENV}/bin/pip" install --no-cache-dir \
      open-webui \
      requests \
      huggingface_hub \
      hf_transfer

COPY run.sh /app/run.sh
RUN chmod +x /app/run.sh

EXPOSE 8000 8080

ENTRYPOINT ["/usr/bin/tini", "--", "/app/run.sh"]
