@echo off
rem OBS VC 实际产量 ~25fps（标称 30），-r 20 让 ffmpeg 复制帧补满 20fps
rem 注意：设备 caps 必须保持 30fps —— 25fps caps 会让希沃堆损坏（0xc0000374）窗口透明
rem akvcam 9.1.3 已应用持久管道补丁（修复每帧新建连接导致的句柄泄漏 ~63/s 和 abort 0x40000015）
rem 上游 9.4.1 将 IPC 重写为 socket 长连接，但存在崩溃问题，故锁定 9.1.3 + backport 补丁
"%~dp0..\tools\ffmpeg\ffmpeg-9.0.1-essentials_build\bin\ffmpeg.exe" -hide_banner -loglevel error -f dshow -i "video=%~1" -video_size %2x%3 -framerate %4 -f rawvideo -r 19 -pix_fmt bgr24 - | "%~dp0..\tools\akvcam913\x86\AkVCamManager.exe" stream %5 RGB24 %2 %3
