..\..\uasm64 -win64 -c -Zp8 -Zi -Zd -Zf win64_1.asm
..\..\uasm64 -win64 -c -Zp8 -Zi -Zd -Zf win64_2.asm
..\..\uasm64 -win64 -c -Zp8 -Zi -Zd -Zf win64_3.asm
..\..\uasm64 -win64 -c -Zp8 -Zi -Zd -Zf win64_3e.asm
..\..\uasm64 -win64 -c -Zp8 -Zi -Zd -Zf win64_4.asm
..\..\uasm64 -win64 -c -Zp8 -Zi -Zd -Zf win64_5.asm
..\..\uasm64 -win64 -c -Zp8 -Zi -Zd -Zf win64_5m.asm
..\..\uasm64 -win64 -c -Zp8 -Zi -Zd -Zf win64_5x.asm
..\..\uasm64 -win64 -c -Zp8 -Zi -Zd -Zf win64_6.asm
..\..\uasm64 -pe win64_6p.asm
..\..\uasm64 -win64 -c -Zp8 -Zi -Zd -Zf win64_6x.asm
..\..\uasm64 -pe win64_8.asm
..\..\uasm64 -win64 -c -Zp8 -Zi -Zd -Zf win64_9a.asm
..\..\uasm64 -win64 -c -Zp8 -Zi -Zd -Zf win64_9d.asm

..\..\uasm64 -win64 -c -Zp8 -Zi -Zd -Zf oo1.asm

"C:\Program Files (x86)\Microsoft Visual Studio\2017\Professional\VC\Tools\MSVC\14.11.25503\bin\HostX86\x64\link.exe" /subsystem:windows /entry:main /machine:x64 /debug /Libpath:"%WINSDK%\v7.1\Lib\x64" win64_1.obj
"C:\Program Files (x86)\Microsoft Visual Studio\2017\Professional\VC\Tools\MSVC\14.11.25503\bin\HostX86\x64\link.exe" /subsystem:windows /machine:x64 /debug /Libpath:"%WINSDK%\v7.1\Lib\x64" win64_2.obj kernel32.lib user32.lib
"C:\Program Files (x86)\Microsoft Visual Studio\2017\Professional\VC\Tools\MSVC\14.11.25503\bin\HostX86\x64\link.exe" /subsystem:windows /machine:x64 /debug /Libpath:"%WINSDK%\v7.1\Lib\x64" win64_3.obj 
"C:\Program Files (x86)\Microsoft Visual Studio\2017\Professional\VC\Tools\MSVC\14.11.25503\bin\HostX86\x64\link.exe" /subsystem:windows /machine:x64 /debug /Libpath:"%WINSDK%\v7.1\Lib\x64" win64_3e.obj 
"C:\Program Files (x86)\Microsoft Visual Studio\2017\Professional\VC\Tools\MSVC\14.11.25503\bin\HostX86\x64\link.exe" /subsystem:console /machine:x64 /debug /Libpath:"%WINSDK%\v7.1\Lib\x64" win64_4.obj 
"C:\Program Files (x86)\Microsoft Visual Studio\2017\Professional\VC\Tools\MSVC\14.11.25503\bin\HostX86\x64\link.exe" /subsystem:console /machine:x64 /debug /Libpath:"%WINSDK%\v7.1\Lib\x64" win64_5.obj 
"C:\Program Files (x86)\Microsoft Visual Studio\2017\Professional\VC\Tools\MSVC\14.11.25503\bin\HostX86\x64\link.exe" /subsystem:console /machine:x64 /debug win64_5m.obj c:\jwasm\wininc\Lib64\msvcrt.lib
"C:\Program Files (x86)\Microsoft Visual Studio\2017\Professional\VC\Tools\MSVC\14.11.25503\bin\HostX86\x64\link.exe" /subsystem:console /machine:x64 /debug win64_5x.obj c:\jwasm\wininc\Lib64\msvcrt.lib
"C:\Program Files (x86)\Microsoft Visual Studio\2017\Professional\VC\Tools\MSVC\14.11.25503\bin\HostX86\x64\link.exe" /subsystem:console /machine:x64 /debug /Libpath:"%WINSDK%\v7.1\Lib\x64" win64_6.obj msvcrt.lib
"C:\Program Files (x86)\Microsoft Visual Studio\2017\Professional\VC\Tools\MSVC\14.11.25503\bin\HostX86\x64\link.exe" /subsystem:console /machine:x64 /debug /Libpath:"%WINSDK%\v7.1\Lib\x64" win64_6x.obj msvcrt.lib
"C:\Program Files (x86)\Microsoft Visual Studio\2017\Professional\VC\Tools\MSVC\14.11.25503\bin\HostX86\x64\link.exe" /dll /machine:x64 /debug /Libpath:"%WINSDK%\v7.1\Lib\x64" win64_9d.obj 
"C:\Program Files (x86)\Microsoft Visual Studio\2017\Professional\VC\Tools\MSVC\14.11.25503\bin\HostX86\x64\link.exe" /subsystem:console /machine:x64 /debug /Libpath:"%WINSDK%\v7.1\Lib\x64" win64_9a.obj win64_9d.lib 
"C:\Program Files (x86)\Microsoft Visual Studio\2017\Professional\VC\Tools\MSVC\14.11.25503\bin\HostX86\x64\link.exe" /subsystem:console /machine:x64 /debug /Libpath:"%WINSDK%\v7.1\Lib\x64" oo1.obj
