@echo off
rem specclaw Windows shim - lets cmd.exe / PowerShell run the sibling bash script
rem of the same name. Git Bash ignores this file and uses the extensionless one.
setlocal EnableDelayedExpansion
set "SPECCLAW_BASH="
set "SPECCLAW_GITROOT="

rem Locate Git for Windows through git.exe, which is normally on PATH (Git\cmd)
rem while bash.exe and the MSYS utilities are not.
for /f "delims=" %%g in ('where git.exe 2^>nul') do (
  if not defined SPECCLAW_GITROOT for %%r in ("%%~dpg..") do set "SPECCLAW_GITROOT=%%~fr"
)

if defined SPECCLAW_GITROOT (
  if exist "!SPECCLAW_GITROOT!\usr\bin\bash.exe" set "SPECCLAW_BASH=!SPECCLAW_GITROOT!\usr\bin\bash.exe"
  if not defined SPECCLAW_BASH if exist "!SPECCLAW_GITROOT!\bin\bash.exe" set "SPECCLAW_BASH=!SPECCLAW_GITROOT!\bin\bash.exe"
)

rem Fall back to a bash on PATH, but never System32\bash.exe - that is the WSL
rem launcher, which cannot see the Windows paths these scripts are handed.
if not defined SPECCLAW_BASH (
  for /f "delims=" %%b in ('where bash.exe 2^>nul') do (
    if not defined SPECCLAW_BASH echo %%b | find /i "\System32\" >nul || set "SPECCLAW_BASH=%%b"
  )
)

if not defined SPECCLAW_BASH (
  echo ERROR: specclaw could not find bash.exe.>&2
  echo Install Git for Windows ^(https://git-scm.com/download/win^) or run this from Git Bash.>&2
  exit /b 127
)

rem bash.exe invoked directly is NOT a login shell, so /etc/profile never runs and
rem the MSYS utilities (curl, sed, grep, awk...) are missing from PATH - Windows'
rem own curl.exe would win and break scripts in confusing ways. Put MSYS first.
if defined SPECCLAW_GITROOT (
  if exist "!SPECCLAW_GITROOT!\mingw64\bin" set "PATH=!SPECCLAW_GITROOT!\mingw64\bin;!PATH!"
  if exist "!SPECCLAW_GITROOT!\usr\bin" set "PATH=!SPECCLAW_GITROOT!\usr\bin;!PATH!"
)

"!SPECCLAW_BASH!" "%~dp0%~n0" %*
exit /b !errorlevel!
