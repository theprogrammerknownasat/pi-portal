#!/usr/bin/env bash

# russian-roulette.sh
# “True” Russian Roulette: absolutely any process (including PID 1 or this script) can be killed.

# --- Configuration ---
SCORE_FILE="$HOME/.rr_score"
HIGH_FILE="$HOME/.rr_highscore"

# --- Initialization ---
mkdir -p "$(dirname "$SCORE_FILE")"
touch "$SCORE_FILE" "$HIGH_FILE"
SCORE="$(<"$SCORE_FILE" 2>/dev/null || echo 0)"
HIGH="$(<"$HIGH_FILE" 2>/dev/null  || echo 0)"

# --- Must be root to kill PID 1 etc. ---
if [[ $EUID -ne 0 ]]; then
  echo "⚠️  Must be run as root (or via sudo)."
  exit 1
fi

# --- Save (and bump high) ---
save_scores() {
  echo "$SCORE" > "$SCORE_FILE"
  if (( SCORE > HIGH )); then
    echo "$SCORE" > "$HIGH_FILE"
  fi
}

# --- Main Loop ---
while true; do
  echo
  echo "Current score: $SCORE    High score: $HIGH"
  read -rp "[h]it the trigger or [q]uit? " choice

  case "$choice" in
    h|hit)
      # bump score & save before any kill
      (( SCORE++ ))
      save_scores

      # grab *all* PIDs, no filtering
      mapfile -t PIDS < <(ps -e -o pid= | tr -d ' ')

      # pick a random one
      idx=$(( RANDOM % ${#PIDS[@]} ))
      target=${PIDS[$idx]}

      # do the deed
      if kill -9 "$target" 2>/dev/null; then
        echo "💥 Bang! Killed PID $target."
      else
        echo "⚠️  Tried to kill PID $target, but failed (maybe it's already gone)."
      fi
      ;;
    q|quit)
      echo
      echo "You walked away with score $SCORE (high score: $HIGH)."
      exit 0
      ;;
    *)
      echo "Please type 'h' (hit) or 'q' (quit)."
      ;;
  esac
done
