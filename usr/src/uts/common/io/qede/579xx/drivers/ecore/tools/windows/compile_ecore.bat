@echo off

path=%path%;%cd%\bin
set flags=-DCONFIG_ECORE_L2 -DCONFIG_ECORE_ROCE -DCONFIG_ECORE_FCOE -DCONFIG_ECORE_ISCSI -DCONFIG_ECORE_LL2 -DCONFIG_ECORE_SRIOV -DECORE_PACKAGE -I./include -I./../../hsi/hw/ -I./../../hsi/mcp/
pushd ..\..\

tools\windows\bin\gcc.exe -c *.c %flags%

popd

if "%1"=="TESTMACHINE" exit %ERRORLEVEL%