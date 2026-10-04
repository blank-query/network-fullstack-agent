#!/bin/bash
# Runs the face and the voice line in tmux, each in its own restart loop,
# so a crash restarts just that process and the container stays up to be
# entered: `docker exec -it jarvis tmux attach -t voice` types into the
# live voice session (detach with Ctrl-b d, never Ctrl-c).
set -u

tmux new-session -d -s face \
  "while true; do cd /opt/jarvis/ai-visualizer && python server.py --no-open; echo 'face exited, restarting in 3s'; sleep 3; done"

tmux new-session -d -s voice \
  "while true; do cd /opt/jarvis/backtalk && xvfb-run -a python -m backtalk.main; echo 'voice line exited, restarting in 3s'; sleep 3; done"

trap 'tmux kill-server 2>/dev/null; exit 0' TERM INT
while tmux has-session 2>/dev/null; do sleep 5 & wait $!; done
echo "tmux server is gone; exiting so Docker restarts the container"
exit 1
