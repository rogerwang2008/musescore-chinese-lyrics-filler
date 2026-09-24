@echo off
rem ====================================================================
rem  Lyrics Filler installer
rem
rem    install.bat                            install into the default
rem                                           MuseScore user plugins folder
rem    install.bat "D:\My MuseScore\Plugins"  install into that folder
rem
rem  WHY THIS FILE IS ASCII-ONLY / ENGLISH-ONLY
rem  cmd.exe tracks its position in the batch file by byte offset, and that
rem  bookkeeping breaks once the file contains multi-byte text (the classic
rem  "chcp 65001 + UTF-8 batch" bug): lines after the Chinese get re-split,
rem  so a REM or echo tail ends up executed as a command. That is exactly the
rem  "'?>' is not recognized as an internal or external command" failure this
rem  script used to produce. Keeping the script ASCII makes it parse the same
rem  on every code page. Chinese install instructions live in README.md, and
rem  install.sh (bash reads UTF-8 fine) keeps its Chinese output.
rem ====================================================================

setlocal enableextensions
set "RC=0"
set "DOCS="
set "PERSONAL="

set "SRC=%~dp0LyricsFiller"
if not exist "%SRC%\lyricsfiller.qml" goto SRC_MISSING

rem Target folder priority: argument, then the real Documents folder from the
rem registry, then %USERPROFILE%\Documents as a last resort. The registry read
rem matters because Documents is frequently redirected (OneDrive, or a second
rem drive) -- %USERPROFILE%\Documents then points somewhere MuseScore never
rem scans, and the plugin silently fails to show up.
set "DEST=%~1"
if not "%DEST%"=="" goto DEST_READY

for /f "tokens=1,2,*" %%a in ('reg query "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\User Shell Folders" /v Personal 2^>nul ^| findstr /i "Personal"') do set "PERSONAL=%%c"

rem The registry value is REG_EXPAND_SZ, so it may still read %USERPROFILE%\...
rem "call set" runs a second expansion pass and resolves it.
if not "%PERSONAL%"=="" call set "DOCS=%PERSONAL%"
if not "%DOCS%"=="" goto DOCS_READY
set "DOCS=%USERPROFILE%\Documents"
:DOCS_READY
set "DEST=%DOCS%\MuseScore4\Plugins"
:DEST_READY

echo Source: %SRC%
echo Target: %DEST%\LyricsFiller
echo.

if not exist "%DEST%" mkdir "%DEST%"
if not exist "%DEST%" goto MKDIR_FAILED

rem findstr, not find: find collides with coreutils find when Git Bash's PATH
rem leaks into cmd, which turns /i into a file name.
tasklist /fi "imagename eq MuseScore4.exe" 2>nul | findstr /i /c:"MuseScore4.exe" >nul
if not errorlevel 1 echo NOTE: MuseScore is running. Quit it completely before testing.
echo.

xcopy /e /i /y /q "%SRC%" "%DEST%\LyricsFiller" >nul
if errorlevel 1 goto COPY_FAILED

if not exist "%DEST%\LyricsFiller\lyricsfiller.qml" goto VERIFY_FAILED

echo Done.
echo.
echo Next: quit MuseScore Studio completely and reopen it.
echo "Reload plugins" only rescans the list, it does not recompile QML.
echo Then open Plugins - Lyrics - "Lyrics Filler".
echo Not there? Check Edit - Preferences - Extensions - "My plugins" folder:
echo it must be the Target path printed above.
goto REPORT

:SRC_MISSING
echo ERROR: plugin source not found: %SRC%\lyricsfiller.qml
echo Run this script from the repository root.
set "RC=1"
goto REPORT

:MKDIR_FAILED
echo ERROR: cannot create target folder: %DEST%
echo Pass a writable path instead: install.bat "D:\path\to\Plugins"
set "RC=1"
goto REPORT

:COPY_FAILED
echo ERROR: copy failed. Quit MuseScore and try again.
set "RC=1"
goto REPORT

:VERIFY_FAILED
echo ERROR: xcopy reported success but %DEST%\LyricsFiller\lyricsfiller.qml is missing
set "RC=1"
goto REPORT

:REPORT
rem A double-clicked console window closes instantly, so only pause in that case.
echo %cmdcmdline% | findstr /i /c:"%~f0" >nul && pause
endlocal
exit /b %RC%
