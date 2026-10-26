@echo off
rem Launches OctoWoW with the ReShade Vulkan layer enabled for THIS process tree only.
rem No registry/system change. Normal launch (without this file) is untouched.
set VK_ADD_IMPLICIT_LAYER_PATH=D:\Octowow\reshade
cd /d D:\Octowow
start "" VanillaFixes.exe
