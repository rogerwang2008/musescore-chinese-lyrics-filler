#!/usr/bin/env bash
# 把 LyricsFiller 插件目录复制到 MuseScore Studio 4.x 的用户插件目录。
#
#   ./install.sh                # 安装到默认目录
#   ./install.sh /some/path     # 安装到指定目录
#
# MuseScore 4 的默认用户插件目录是"文档/MuseScore4/Plugins"
# （见源码 ExtensionsConfiguration::pluginsUserPath，默认为 userDataPath + "/Plugins"，
# 而 userDataPath 就是"文档/MuseScore4"）。
# 如果你在 MuseScore 的 编辑 → 偏好设置 → 扩展 里改过这个路径，请把新路径作为参数传进来。

set -euo pipefail

SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/LyricsFiller"

if [ ! -f "$SRC/lyricsfiller.qml" ]; then
    echo "找不到插件源文件：$SRC" >&2
    exit 1
fi

if [ $# -ge 1 ]; then
    DEST="$1"
else
    CANDIDATE="$HOME/Documents/MuseScore4/Plugins"
    # 中文/德语等系统里"文档"可能被重定向到其他盘，先找找已有的 MuseScore4 目录
    if [ ! -d "$HOME/Documents/MuseScore4" ]; then
        FOUND="$(find "$HOME" -maxdepth 4 -type d -name MuseScore4 2>/dev/null | head -n 1 || true)"
        if [ -n "$FOUND" ]; then
            CANDIDATE="$FOUND/Plugins"
        fi
    fi
    DEST="$CANDIDATE"
fi

mkdir -p "$DEST"

if [ -z "$DEST" ] || [ "$DEST" = "/" ]; then
    echo "目标路径异常，已中止：'$DEST'" >&2
    exit 1
fi

# 只覆盖本插件自己的目录，避免留下改名前的旧文件
if [ -d "$DEST/LyricsFiller" ]; then
    rm -rf "$DEST/LyricsFiller"
fi
cp -R "$SRC" "$DEST/LyricsFiller"

echo "已安装到：$DEST/LyricsFiller"
echo "重启 MuseScore Studio，在 插件 → 歌词 (Lyrics) 菜单里找 “Lyrics Filler 自动填词”。"
echo "如果菜单里没有，请检查 编辑 → 偏好设置 → 扩展 里的“我的插件”路径是否为上面的目录。"
