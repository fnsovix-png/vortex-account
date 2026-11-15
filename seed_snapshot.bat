@echo off
rem Uploads the local account data once, so the hosted server starts with the
rem real accounts, sessions, profiles and saves instead of an empty database.
rem   set VORTEX_REDIS_URL=rediss://...   (Upstash dashboard > Connect)
rem   seed_snapshot.bat [data-dir]        (default C:\VortexServerData)
setlocal
if "%VORTEX_REDIS_URL%"=="" (
  echo Set VORTEX_REDIS_URL first.
  exit /b 1
)
set DATA=%~1
if "%DATA%"=="" set DATA=C:\VortexServerData
python "%~dp0seed_snapshot.py" "%DATA%"
