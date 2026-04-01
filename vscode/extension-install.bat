@echo off
setlocal enabledelayedexpansion

set "SCRIPT_DIR=%~dp0"
set "EXTENSIONS_FILE=%SCRIPT_DIR%extensions.txt"

for /f "usebackq delims=" %%E in ("%EXTENSIONS_FILE%") do (
  if not "%%E"=="" (
    code --install-extension "%%E" --force
  )
)
