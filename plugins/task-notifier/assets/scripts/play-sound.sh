#!/bin/bash
# 跨平台系统通知脚本 — 作为 Claude Code Stop/PermissionRequest hook 运行
# 使用自定义 MP3 文件
# 支持场景：stop (对话结束), permission (权限请求)
#
# Hook 协议要求：
#   - stdout 留空（不输出 JSON 即表示 non-blocking / allow）
#   - stderr 静默（避免 hook runner 报告 "non-blocking status code" 噪音）
#   - 始终 exit 0

# 获取场景参数
SCENE="${1:-stop}"

# 所有调试输出重定向到 /dev/null（hook 上下文不需要调试信息）
exec 2>/dev/null

# 检测操作系统
detect_os() {
    case "$(uname -s)" in
        Darwin*)    echo "macOS" ;;
        Linux*)     echo "Linux" ;;
        CYGWIN*|MINGW*|MSYS*) echo "Windows" ;;
        *)          echo "Unknown" ;;
    esac
}

# 获取脚本所在目录
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# 获取自定义 MP3 文件路径
get_custom_sound_file() {
    local custom_file

    case "$SCENE" in
        permission)
            custom_file="$PLUGIN_ROOT/assets/sounds/confirm.mp3"
            ;;
        stop|*)
            custom_file="$PLUGIN_ROOT/assets/sounds/freesound_community-goodresult-82807.mp3"
            ;;
    esac

    if [ -f "$custom_file" ]; then
        echo "$custom_file"
        return 0
    fi
    return 1
}

# 播放自定义 MP3 文件
play_custom_sound() {
    local sound_file="$1"
    [ -z "$sound_file" ] || [ ! -f "$sound_file" ] && return 1

    local os
    os=$(detect_os)
    case "$os" in
        macOS)
            command -v afplay >/dev/null 2>&1 && { afplay "$sound_file" & disown; return 0; }
            ;;
        Linux)
            command -v mpv >/dev/null 2>&1 && { mpv --no-video --really-quiet "$sound_file" & disown; return 0; }
            command -v mplayer >/dev/null 2>&1 && { mplayer -really-quiet "$sound_file" & disown; return 0; }
            command -v paplay >/dev/null 2>&1 && { paplay "$sound_file" & disown; return 0; }
            command -v aplay >/dev/null 2>&1 && { aplay "$sound_file" & disown; return 0; }
            ;;
        Windows)
            command -v powershell >/dev/null 2>&1 && {
                powershell -Command "\$player = New-Object System.Media.SoundPlayer; \$player.SoundLocation = '$sound_file'; \$player.Play()" & disown
                return 0
            }
            ;;
    esac
    return 1
}

# 播放系统默认通知（降级方案）
play_system_notification() {
    local os
    os=$(detect_os)

    case "$os" in
        macOS)
            osascript -e 'display notification "任务已完成" with title "Claude Code" sound name "Glass"' &
            disown
            ;;
        Linux)
            command -v notify-send >/dev/null 2>&1 && notify-send "Claude Code" "任务已完成"
            printf '\a'
            ;;
        Windows|*)
            printf '\a'
            ;;
    esac
}

# 主逻辑：尝试自定义音效，失败则降级到系统通知
if custom_file=$(get_custom_sound_file) && play_custom_sound "$custom_file"; then
    :
else
    play_system_notification
fi

exit 0
