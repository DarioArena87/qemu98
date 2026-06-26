..\..\HJWasm2.13.1s\HJWasm2.13.1s\x64\Release\uasm -win64 -c -Zp8 -Zi -Zd -Zf c_invoke.asm
"C:\Program Files (x86)\Microsoft Visual Studio\2017\Professional\VC\Tools\MSVC\14.12.25827\bin\HostX86\x64\link.exe" /subsystem:console /machine:x64 /debug /Libpath:"%WINSDK%\v7.1\Lib\x64" c_invoke.obj msvcrt.lib

..\..\HJWasm2.13.1s\HJWasm2.13.1s\x64\Release\uasm -win64 -c -Zp8 -Zi -Zd -Zf oo.asm
"C:\Program Files (x86)\Microsoft Visual Studio\2017\Professional\VC\Tools\MSVC\14.12.25827\bin\HostX86\x64\link.exe" /subsystem:console /machine:x64 /debug /Libpath:"%WINSDK%\v7.1\Lib\x64" oo.obj

