#!/bin/bash

SCENE="${1:-stop}"
VOLUME="${AUTOPILOT_CODEX_NOTIFY_VOLUME:-0.8}"

# Keep hooks quiet unless debug logging is explicitly requested.
exec 2>/dev/null

log_debug() {
    if [ -n "${AUTOPILOT_CODEX_NOTIFY_LOG:-}" ]; then
        printf '%s scene=%s pwd=%s %s\n' \
            "$(date '+%Y-%m-%d %H:%M:%S')" \
            "$SCENE" \
            "$(pwd)" \
            "${1:-}" >>"$AUTOPILOT_CODEX_NOTIFY_LOG"
    fi
}

detect_os() {
    case "$(uname -s)" in
        Darwin*) echo "macOS" ;;
        Linux*) echo "Linux" ;;
        CYGWIN*|MINGW*|MSYS*) echo "Windows" ;;
        *) echo "Unknown" ;;
    esac
}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
SOUND_FILE="$PLUGIN_ROOT/assets/sounds/freesound_community-goodresult-82807.mp3"
MACOS_FALLBACK_SOUND="/System/Library/Sounds/Glass.aiff"

run_detached() {
    nohup "$@" >/dev/null 2>&1 </dev/null &
}

play_custom_sound() {
    [ -f "$SOUND_FILE" ] || return 1

    case "$(detect_os)" in
        macOS)
            command -v afplay >/dev/null 2>&1 && {
                log_debug "method=afplay-custom volume=$VOLUME file=$SOUND_FILE"
                run_detached afplay -v "$VOLUME" "$SOUND_FILE"
                return 0
            }
            ;;
        Linux)
            command -v mpv >/dev/null 2>&1 && {
                log_debug "method=mpv-custom file=$SOUND_FILE"
                run_detached mpv --no-video --really-quiet "$SOUND_FILE"
                return 0
            }
            command -v mplayer >/dev/null 2>&1 && {
                log_debug "method=mplayer-custom file=$SOUND_FILE"
                run_detached mplayer -really-quiet "$SOUND_FILE"
                return 0
            }
            command -v paplay >/dev/null 2>&1 && {
                log_debug "method=paplay-custom file=$SOUND_FILE"
                run_detached paplay "$SOUND_FILE"
                return 0
            }
            command -v aplay >/dev/null 2>&1 && {
                log_debug "method=aplay-custom file=$SOUND_FILE"
                run_detached aplay "$SOUND_FILE"
                return 0
            }
            ;;
        Windows)
            command -v powershell >/dev/null 2>&1 && {
                log_debug "method=powershell-custom file=$SOUND_FILE"
                run_detached powershell -Command "\$player = New-Object System.Media.SoundPlayer; \$player.SoundLocation = '$SOUND_FILE'; \$player.Play()"
                return 0
            }
            ;;
    esac

    return 1
}

play_builtin_sound() {
    case "$(detect_os)" in
        macOS)
            [ -f "$MACOS_FALLBACK_SOUND" ] || return 1
            command -v afplay >/dev/null 2>&1 || return 1
            log_debug "method=afplay-fallback volume=$VOLUME file=$MACOS_FALLBACK_SOUND"
            run_detached afplay -v "$VOLUME" "$MACOS_FALLBACK_SOUND"
            return 0
            ;;
    esac

    return 1
}

play_system_notification() {
    case "$(detect_os)" in
        macOS)
            log_debug "method=osascript-notification"
            run_detached osascript -e 'display notification "Task completed" with title "Autopilot for Codex" sound name "Glass"'
            ;;
        Linux)
            log_debug "method=notify-send"
            command -v notify-send >/dev/null 2>&1 && notify-send "Autopilot for Codex" "Task completed"
            printf '\a'
            ;;
        Windows|*)
            log_debug "method=terminal-bell"
            printf '\a'
            ;;
    esac
}

log_debug "method=start"

if ! play_custom_sound && ! play_builtin_sound; then
    play_system_notification
fi

exit 0
