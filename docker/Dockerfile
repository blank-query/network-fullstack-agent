# syntax=docker/dockerfile:1
# Jarvis for a home server: backtalk (voice line + browser bridge) and
# ai-visualizer (the face), both from blank-query's `remote` branches.
# The browser does mic and playback, so no audio devices are needed here.
FROM python:3.11-slim-bookworm

ARG UID=1000
ARG USERNAME=jarvis
# xvfb: pynput's keyboard listener needs an X display even when nothing
# ever presses the key. espeak-ng: Piper's phonemizer. build-essential is
# only for webrtcvad's sdist and is removed in the same layer.
RUN apt-get update && apt-get install -y --no-install-recommends \
        tmux xvfb xauth espeak-ng libportaudio2 libsndfile1 tzdata \
        curl ca-certificates procps build-essential \
    && pip install --no-cache-dir \
        claude-agent-sdk==0.2.163 \
        faster-whisper==1.2.1 \
        moonshine-voice==0.1.5 \
        piper-tts==1.8.0 \
        sherpa-onnx==1.13.8 \
        httpx==0.28.1 \
        numpy==2.4.6 \
        pynput==1.8.2 \
        "setuptools<81" \
        sounddevice==0.5.6 \
        soundfile==0.14.0 \
        webrtcvad==2.0.10 \
        websockets==17.2 \
    && apt-get purge -y build-essential && apt-get autoremove -y \
    && rm -rf /var/lib/apt/lists/*
RUN useradd -m -u ${UID} -s /bin/bash ${USERNAME}

# Whisper lives in the image. The Piper voice is downloaded on first start
# into the models volume instead (each voice has its own license; see
# entrypoint.sh). Kokoro, and PyTorch with it, is deliberately absent:
# backtalk only imports Kokoro if Piper fails.
ENV HF_HOME=/opt/models/hf
RUN python -c "from faster_whisper import WhisperModel; WhisperModel('base.en', device='cpu', compute_type='int8')" \
    && chmod -R a+rX /opt/models

# The code, rebuilt from the current branch heads on every `build`.
ADD --keep-git-dir=true https://github.com/blank-query/network-backtalk.git#remote /opt/jarvis/backtalk
ADD --keep-git-dir=true https://github.com/blank-query/network-ai-visualizer.git#remote /opt/jarvis/ai-visualizer

# `claude` on PATH for `docker exec -it jarvis claude --resume <id>`: the
# same CLI the SDK bundles and the voice line already runs.
RUN ln -s "$(python -c 'import claude_agent_sdk, os; print(os.path.dirname(claude_agent_sdk.__file__))')/_bundled/claude" /usr/local/bin/claude \
    && mkdir -p /opt/jarvis/backtalk/logs /data/signals /data/models /data/run /home/${USERNAME}/projects/Jarvis \
    && chown -R ${USERNAME}:${USERNAME} /opt/jarvis /data /home/${USERNAME}

COPY --chmod=755 entrypoint.sh /usr/local/bin/jarvis-entrypoint

USER ${USERNAME}
WORKDIR /home/${USERNAME}/projects/Jarvis
# 8790: the face (web page). 8792: the voice bridge (websocket).
EXPOSE 8790 8792
LABEL org.opencontainers.image.source=https://github.com/blank-query/network-fullstack-agent \
      org.opencontainers.image.description="Voice and face for a Claude Code agent, reached from a browser" \
      org.opencontainers.image.licenses=AGPL-3.0-or-later
ENTRYPOINT ["jarvis-entrypoint"]
