@echo off
rem Double-click this file to run the Arcadia prototype test.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0run_tests.ps1" %*
