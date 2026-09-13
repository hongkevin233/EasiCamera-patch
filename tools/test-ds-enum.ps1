# 用希沃同款路径（DirectShowLib 枚举 VideoInputDeviceCategory）验证虚拟设备可见性
param([string]$dll = 'D:\easi-connector\easi-soft\EasiCamera_2.1.0.4410\Main\DirectShowLib.dll')

[System.Reflection.Assembly]::LoadFrom($dll) | Out-Null
# 直接看希沃代码用的分类：MultimediaUtil.PhysicsVideoInputDevices → DsDevice.GetDevicesOfCat(FilterCategory.VideoInputDevice)
$cat = [DirectShowLib.FilterCategory]::VideoInputDevice
$devices = [DirectShowLib.DsDevice]::GetDevicesOfCat($cat)
Write-Output ("DirectShow video input devices: " + $devices.Count)
foreach ($d in $devices) {
    Write-Output ("  - Name: " + $d.Name)
    Write-Output ("    Path: " + $d.DevicePath)
    $isVirtual = $d.Name.ToLowerInvariant().Contains('virtual')
    Write-Output ("    name-contains-virtual: " + $isVirtual + "  (true 则被希沃剔除)")
}
