@echo off
REM BUILD_VXD.BAT — Build HYPBACK.VXD on a Win9x guest
REM
REM Detects available build tools and compiles the VxD driver.
REM Supports: Microsoft DDK (MASM 6.11+), JWasm, Visual Studio
REM
REM Usage: BUILD_VXD.BAT [target_dir] [ddk_path]
REM         target_dir defaults to C:\WINDOWS\SYSTEM\VMM32
REM         ddk_path   custom DDK location (e.g., C:\MSDDK)

setlocal enabledelayedexpansion
set TARGET=%1
if "%TARGET%"=="" set TARGET=C:\WINDOWS\SYSTEM\VMM32
set DDK_CUSTOM=%2
set SRC=%~dp0

echo ============================================================
echo  QEMU98 Guest Tools — HYPBACK.VXD Build Script
echo ============================================================
echo.
echo Target directory: %TARGET%
echo Source directory:  %SRC%
if not "%DDK_CUSTOM%"=="" echo Custom DDK path:   %DDK_CUSTOM%
echo.

REM ---- Detect assembler ----
set ASM=
set ASM_NAME=
set INC_PATH=

REM Priority 0: Custom DDK path from command line
if not "%DDK_CUSTOM%"=="" (
    if exist "%DDK_CUSTOM%\bin\ml.exe" (
        set ASM=%DDK_CUSTOM%\bin\ml.exe
        set ASM_NAME=Microsoft DDK MASM
        set INC_PATH=%DDK_CUSTOM%\inc\win98
        goto :found_asm
    )
    echo [WARN] Custom DDK path specified but ml.exe not found at %DDK_CUSTOM%\bin\
    echo.
)

REM Priority 0b: DDK_PATH environment variable
if not "%DDK_PATH%"=="" (
    if exist "%DDK_PATH%\bin\ml.exe" (
        set ASM=%DDK_PATH%\bin\ml.exe
        set ASM_NAME=Microsoft DDK MASM
        set INC_PATH=%DDK_PATH%\inc\win98
        goto :found_asm
    )
)

REM Priority 1: Microsoft DDK (common install paths)
for %%D in (C:\DDK C:\98DDK C:\WIN98DDK C:\MSDDK "C:\Program Files\DDK" C:\PROGRA~1\DDK) do (
    if exist "%%~D\bin\ml.exe" (
        set ASM=%%~D\bin\ml.exe
        set ASM_NAME=Microsoft DDK MASM
        set INC_PATH=%%~D\inc\win98
        goto :found_asm
    )
)

REM Priority 2: JWasm / UASM (bundled on this CD in VXD\tools\uasm\)
echo Checking for bundled assembler in %SRC%tools\uasm\...
if exist "%SRC%tools\uasm\UASM32.EXE" (
    set ASM=%SRC%tools\uasm\UASM32.EXE
    set ASM_NAME=UASM (bundled MASM-compatible assembler)
    set INC_PATH=%SRC%
    goto :found_asm
)
if exist "%SRC%tools\uasm\JWASM.EXE" (
    set ASM=%SRC%tools\uasm\JWASM.EXE
    set ASM_NAME=JWasm (bundled MASM-compatible assembler)
    set INC_PATH=%SRC%
    goto :found_asm
)

REM Priority 2b: JWasm / UASM installed on the system
for %%D in (C:\JWASM C:\UASM "C:\Program Files\JWasm" "C:\Program Files\UASM") do (
    if exist "%%~D\UASM32.EXE" (
        set ASM=%%~D\UASM32.EXE
        set ASM_NAME=UASM
        set INC_PATH=%SRC%
        goto :found_asm
    )
    if exist "%%~D\JWASM.EXE" (
        set ASM=%%~D\JWASM.EXE
        set ASM_NAME=JWasm
        set INC_PATH=%SRC%
        goto :found_asm
    )
)

REM Priority 3: Visual Studio MASM (ml.exe in PATH)
ml /? >nul 2>&1
if not errorlevel 9009 (
    set ASM=ml.exe
    set ASM_NAME=MASM (Visual Studio)
    set INC_PATH=%SRC%
    goto :found_asm
)

REM No assembler found
echo [ERROR] No assembler found! Cannot compile HYPBACK.VXD.
echo.
echo To build HYPBACK.VXD, you need one of:
echo.
echo   1. Microsoft Windows 98 DDK with MASM 6.11+
echo      Install the DDK (default: C:\DDK\)
echo      Or specify custom path: BUILD_VXD C:\WINDOWS\SYSTEM\VMM32 C:\MYDDK
echo      Or set: SET DDK_PATH=C:\MYDDK
echo.
echo   2. JWasm (open-source MASM clone)
echo      Download from https://github.com/JWasm/JWasm
echo      Extract JWASM.EXE to C:\JWASM\
echo.
echo   3. Visual C++ with MASM (ml.exe must be in PATH)
echo.
echo After installing an assembler, run BUILD_VXD.BAT again.
echo.
pause
goto :end

:found_asm
echo [OK] Found assembler: %ASM_NAME%
echo [OK] Assembler path: %ASM%
echo [OK] Include path:  %INC_PATH%
echo.

REM ---- Compile HYPBACK.VXD ----
echo --- Compiling HYPBACK.VXD ---

cd /d "%SRC%"

echo Running: "%ASM%" -c -coff -I"%INC_PATH%" -FoHYPBACK.OBJ hypback.asm
"%ASM%" -c -coff -I"%INC_PATH%" -FoHYPBACK.OBJ hypback.asm

if errorlevel 1 (
    echo.
    echo [ERROR] Assembly failed! See errors above.
    echo.
    echo Troubleshooting:
    echo   - Ensure DDK headers ^(vmm.inc^, vpicd.inc^, shell.inc^) are in %INC_PATH%
    echo   - If using JWasm, stub headers are in the VXD directory
    echo   - JWasm may need the real DDK headers for full compatibility
    echo   - Install the Microsoft DDK for guaranteed compatibility
    goto :end
)

echo [OK] Assembly successful - HYPBACK.OBJ created

REM ---- Link HYPBACK.VXD ----
echo.
echo --- Linking HYPBACK.VXD ---

REM Try MSVC linker
link >nul 2>&1
if not errorlevel 9009 (
    echo Using MSVC LINK.EXE
    link /VXD /NODEFAULTLIB /DEF:hypback.def /OUT:HYPBACK.VXD HYPBACK.OBJ
    if not errorlevel 1 goto :link_ok
)

REM Try DDK linker (same paths as assembler)
if exist "C:\DDK\bin\link.exe" (
    echo Using DDK linker
    C:\DDK\bin\link.exe /VXD /NODEFAULTLIB /DEF:hypback.def /OUT:HYPBACK.VXD HYPBACK.OBJ
    if not errorlevel 1 goto :link_ok
)
if exist "C:\98DDK\bin\link.exe" (
    echo Using 98DDK linker
    C:\98DDK\bin\link.exe /VXD /NODEFAULTLIB /DEF:hypback.def /OUT:HYPBACK.VXD HYPBACK.OBJ
    if not errorlevel 1 goto :link_ok
)
if not "%DDK_CUSTOM%"=="" if exist "%DDK_CUSTOM%\bin\link.exe" (
    echo Using custom DDK linker
    %DDK_CUSTOM%\bin\link.exe /VXD /NODEFAULTLIB /DEF:hypback.def /OUT:HYPBACK.VXD HYPBACK.OBJ
    if not errorlevel 1 goto :link_ok
)
if not "%DDK_PATH%"=="" if exist "%DDK_PATH%\bin\link.exe" (
    echo Using DDK_PATH linker
    %DDK_PATH%\bin\link.exe /VXD /NODEFAULTLIB /DEF:hypback.def /OUT:HYPBACK.VXD HYPBACK.OBJ
    if not errorlevel 1 goto :link_ok
)

REM Try OpenWatcom linker
wlink >nul 2>&1
if not errorlevel 9009 (
    echo Using OpenWatcom wlink
    wlink format dos le name HYPBACK.VXD file HYPBACK.OBJ
    if not errorlevel 1 goto :link_ok
)

echo [ERROR] No linker found! Cannot create HYPBACK.VXD.
echo.
echo The object file HYPBACK.OBJ was created successfully.
echo To complete the build manually:
echo.
echo   MSVC/DDK linker:
echo     LINK /VXD /NODEFAULTLIB /DEF:hypback.def /OUT:HYPBACK.VXD HYPBACK.OBJ
echo.
echo   OpenWatcom linker:
echo     wlink format dos le name HYPBACK.VXD file HYPBACK.OBJ
echo.
goto :end

:link_ok
echo [OK] HYPBACK.VXD created!

REM ---- Install the driver ----
echo.
echo --- Installing HYPBACK.VXD ---

if not exist "%TARGET%" mkdir "%TARGET%"

echo Copying HYPBACK.VXD to %TARGET%\
copy /Y HYPBACK.VXD "%TARGET%\" >nul
if errorlevel 1 (
    echo [ERROR] Failed to copy HYPBACK.VXD to %TARGET%\
    echo Check permissions and disk space.
    goto :end
)
echo [OK] HYPBACK.VXD copied to %TARGET%\

if exist HYPBACK.OBJ del HYPBACK.OBJ

REM ---- SYSTEM.INI configuration ----
:check_system_ini
echo.
echo --- Checking SYSTEM.INI ---

set INI=C:\WINDOWS\SYSTEM.INI
if not exist "%INI%" (
    echo [WARN] SYSTEM.INI not found at %INI%
    echo [WARN] Check your Windows installation.
    goto :summary
)

findstr /i "device=HYPBACK.VXD" "%INI%" >nul 2>&1
if not errorlevel 1 (
    echo [OK] HYPBACK.VXD already configured in SYSTEM.INI
    goto :summary
)

echo.
echo ============================================================
echo  IMPORTANT: Manual step required
echo ============================================================
echo.
echo Add the following line to C:\WINDOWS\SYSTEM.INI
echo under the [386Enh] section:
echo.
echo     device=HYPBACK.VXD
echo.
echo Then reboot Windows to activate the driver.
echo ============================================================

REM ---- Summary ----
:summary
echo.
echo ============================================================
echo  Build Complete
echo ============================================================
echo.
echo Driver: %TARGET%\HYPBACK.VXD
echo.
echo Next steps:
echo   1. Ensure "device=HYPBACK.VXD" is in SYSTEM.INI [386Enh]
echo   2. Reboot Windows 9x
echo   3. Run TEST_HYP.EXE to verify the driver works
echo.
echo For help: see README_VXD.TXT in the VXD directory
echo ============================================================
pause

:end
endlocal
