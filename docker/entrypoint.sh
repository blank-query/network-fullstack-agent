#!/bin/bash
# Starts the face and the voice line, each in its own tmux restart loop,
# so a crash restarts just that process and the container stays up to be
# entered: `docker exec -it jarvis tmux attach -t voice` types into the
# live voice session (detach with Ctrl-b d, never Ctrl-c).
#
# Works with nothing but CLAUDE_CODE_OAUTH_TOKEN set: configs are built
# from environment variables (defaults below), unless a full config is
# mounted at /config/backtalk.json or /config/ai-visualizer.json.
set -u

RUN=/data/run
mkdir -p "$RUN" /data/models/piper

# Piper voice: downloaded once into the models volume rather than shipped
# in the image, since each voice carries its own license.
VOICE="${PIPER_VOICE:-en_GB-semaine-medium}"
if [ ! -f "/data/models/piper/$VOICE.onnx" ]; then
  lang="${VOICE%%_*}"; locale="${VOICE%%-*}"; rest="${VOICE#*-}"
  quality="${rest##*-}"; name="${rest%-*}"
  base="https://huggingface.co/rhasspy/piper-voices/resolve/v1.0.0/$lang/$locale/$name/$quality"
  echo "downloading Piper voice $VOICE..."
  for f in "$VOICE.onnx.json" "$VOICE.onnx"; do
    curl -fsSL -o "/data/models/piper/$f.part" "$base/$f" \
      && mv "/data/models/piper/$f.part" "/data/models/piper/$f" \
      || echo "COULD NOT DOWNLOAD $base/$f: the voice line will have no voice"
  done
fi

if [ -f /config/backtalk.json ]; then
  export BACKTALK_CONFIG=/config/backtalk.json
else
  export BACKTALK_CONFIG="$RUN/backtalk.json"
  python - <<'PY'
import json, os
e = lambda k, d=None: os.environ.get(k) or d
voice = e("PIPER_VOICE", "en_GB-semaine-medium")
default_voice = voice == "en_GB-semaine-medium"
speaker = e("PIPER_SPEAKER", "2" if default_voice else None)
pace = e("PIPER_LENGTH_SCALE", "0.88" if default_voice else None)
agent = e("AGENT_DIR", os.path.expanduser("~/projects/Jarvis"))
cfg = {
    "agent_dir": agent,
    "extra_dirs": [d for d in e("EXTRA_DIRS", "").split(":") if d],
    "name": e("JARVIS_NAME", "Jarvis"),
    "greeting": e("JARVIS_GREETING", "Hello, what are we working on today?"),
    "permission_mode": e("PERMISSION_MODE", "ask"),
    "resume_last_session": e("RESUME_LAST_SESSION", "true") != "false",
    "signals_dir": "/data/signals",
    "mic_mode": "ptt",
    "stt_model": e("STT_MODEL", "base.en"),
    "stt_device": "cpu",
    "piper": {"enabled": True,
              "model_path": f"/data/models/piper/{voice}.onnx",
              "speaker_id": int(speaker) if speaker else None,
              "length_scale": float(pace) if pace else None},
    "web": {"enabled": True, "host": "0.0.0.0", "port": 8792,
            "local_playback_on_remote_turn": False},
}
if e("JARVIS_MODEL"):
    cfg["model"] = cfg["deep_model"] = e("JARVIS_MODEL")
json.dump(cfg, open("/data/run/backtalk.json", "w"), indent=2)

# A brand-new agent folder gets a minimal identity; an existing one is
# never touched.
os.makedirs(agent, exist_ok=True)
md = os.path.join(agent, "CLAUDE.md")
if not os.path.exists(md):
    n = cfg["name"]
    open(md, "w").write(f"# {n}\n\nYou are {n}, a voice assistant people talk to "
                        "from a web browser. Your replies are spoken aloud, so keep "
                        "them short and conversational, with no markdown.\n")
PY
fi

FACE_CFG=/opt/jarvis/ai-visualizer/ai-visualizer.json
if [ -f /config/ai-visualizer.json ]; then
  cp /config/ai-visualizer.json "$FACE_CFG"
else
  python - <<'PY'
import json, os
e = lambda k, d: os.environ.get(k) or d
json.dump({"name": e("JARVIS_NAME", "Jarvis"), "badge": "",
           "face": e("FACE", "bioradial"), "host": "0.0.0.0", "port": 8790,
           "bus_dir": "/data/signals", "thinking_sound": True,
           "backend_ws": e("BACKEND_WS", "ws://localhost:8792")},
          open("/opt/jarvis/ai-visualizer/ai-visualizer.json", "w"), indent=2)
PY
fi

tmux new-session -d -s face \
  "while true; do cd /opt/jarvis/ai-visualizer && python server.py --no-open; echo 'face exited, restarting in 3s'; sleep 3; done"

tmux new-session -d -s voice \
  "while true; do cd /opt/jarvis/backtalk && xvfb-run -a python -m backtalk.main; echo 'voice line exited, restarting in 3s'; sleep 3; done"

trap 'tmux kill-server 2>/dev/null; exit 0' TERM INT
while tmux has-session 2>/dev/null; do sleep 5 & wait $!; done
echo "tmux server is gone; exiting so Docker restarts the container"
exit 1
