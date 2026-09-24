@echo off
rem 把 LyricsFiller 复制到 MuseScore Studio 4.x 的用户插件目录。
rem
rem   install.bat                      安装到 文档\MuseScore4\Plugins
rem   install.bat "D:\My MuseScore\Plugins"   安装到指定目录
rem
setlocal enabledelayedexpansion

set "SRC=%~dp0LyricsFiller"

if not exist "%SRC%\lyricsfiller.qml" (
    echo 找不到插件源文件：%SRC%\lyricsfiller.qml
    exit /b 1
)

if "%~1"=="" (
    set "DEST=%USERPROFILE%\Documents\MuseScore4\Plugins"
) else (
    set "DEST=%~1"
)

if not exist "%DEST%" mkdir "%DEST%"
if exist "%DEST%\LyricsFiller" rmdir /s /q "%DEST%\LyricsFiller"
xcopy /e /i /y /q "%SRC%" "%DEST%\LyricsFiller" >nul

if errorlevel 1 (
    echo 复制失败，请检查是否有权限写入该目录。
    exit /b 1
)

echo 已安装到：%DEST%\LyricsFiller
echo.
echo 重启 MuseScore Studio，在 插件 ^> 歌词 菜单里找 "Lyrics Filler 自动填词"。
echo 如果菜单里没有：编辑 ^> 偏好设置 ^> 扩展，确认"我的插件"路径就是上面的目录。
exit /b 0
