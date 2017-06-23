@echo off

rem Description: Replaces the FW version in the ecore environment with the specified FW, and compiles the ecore environment.
rem Usage:       ReplaceFwAndCompile <Source FW Folder> [File Type]
rem              <FW Dir> should point to a generated FW folder (e.g. nx2\579xx\smc\everest4\Fw\Main\Output\HSI).
rem              <File Type> type of files to be replaced (one of the options below). If omitted, all files are replaced.
rem              - FW_HSI: FW data types and constants.
rem              - FW_TOOLS: FW functions (HSI Func) and Init Tool generated files.

set srcFolder=%1
set dstFolder=%cd%\..\..\
set csvKey=%cd%\..\replace_fw.csv
set type=ALL
if NOT "%2"=="" set type=%2

perl -w replace_fw.pl -i %srcFolder% -d %dstFolder% -c %csvKey% -t %type%
IF NOT "%ERRORLEVEL%"=="0" goto replaceError

compile_ecore.bat
IF NOT "%ERRORLEVEL%"=="0" goto compileError

echo Compilation was successful!

goto :EOF
:replaceError
echo Failed replacing FW!
goto :EOF
:compileError
echo Failed in ecore compilation!
goto :EOF