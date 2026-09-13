# 探测 DirectShow 摄像头能力：IAMStreamConfig 可用性 + 支持的格式（subtype/分辨率）
# 与希沃 WPFMediaKit 同路径，用于诊断灰屏
param([string]$dll = 'D:\easi-connector\easi-soft\EasiCamera_2.1.0.4410\Main\DirectShowLib.dll')

[System.Reflection.Assembly]::LoadFrom($dll) | Out-Null

$names = @{ 
    [Guid]'32595559-0000-0010-8000-00AA00389B71' = 'YUY2'
    [Guid]'47504A4D-0000-0010-8000-00AA00389B71' = 'MJPG'
    [Guid]'3231564E-0000-0010-8000-00AA00389B71' = 'NV12'
    [Guid]'59565955-0000-0010-8000-00AA00389B71' = 'UYVY'
    [Guid]'00000016-0000-0010-8000-00AA00389B71' = 'RGB4'
    [Guid]'00000015-0000-0010-8000-00AA00389B71' = 'RGB24'
    [Guid]'59BFEA00-4F60-59D7-E5D7-28BEC1D0E85B' = 'H264'
}
function SubName([Guid]$g) { if ($names.ContainsKey($g)) { return $names[$g] } else { return $g.ToString('B').Substring(26, 4) } }

$devices = [DirectShowLib.DsDevice]::GetDevicesOfCat([DirectShowLib.FilterCategory]::VideoInputDevice)
foreach ($d in $devices) {
    Write-Output ("=== " + $d.Name + " ===")
    $filterGuid = [Guid]'083886C1-5ADE-4B5C-BA08-60B4F0B2D278' # IBaseFilter
    $iidRef = [ref]$filterGuid
    $mon = [DirectShowLib.IMoniker]$d.Mon
    $obj = $mon.BindToObject($null, $null, $iidRef)
    $filter = [DirectShowLib.IBaseFilter]$obj
    $pe = $null
    try {
        $filter.EnumPins([ref]$pe) | Out-Null
        $pins = [DirectShowLib.IBaseFilter].GetMethod('EnumPins')
        $pinList = @()
        $pinsArr = New-Object DirectShowLib.IPin[] 1
        while ($pe.Next(1, $pinsArr, [IntPtr]::Zero) -eq 0) { $pinList += $pinsArr[0] }
        foreach ($pin in $pinList) {
            $info = New-Object DirectShowLib.PinInfo
            $pin.QueryPinInfo([ref]$info) | Out-Null
            if ($info.dir -ne [DirectShowLib.PinDirection]::Output) { [System.Runtime.InteropServices.Marshal]::ReleaseComObject($info.filter) | Out-Null; continue }
            $cfg = $pin -as [DirectShowLib.IAMStreamConfig]
            if ($cfg -eq $null) { Write-Output '  [output pin] NO IAMStreamConfig'; continue }
            $count = 0; $size = 0
            $cfg.GetNumberOfCapabilities([ref]$count, [ref]$size) | Out-Null
            Write-Output ("  [output pin] IAMStreamConfig OK, formats: " + $count)
            $mt = New-Object DirectShowLib.AMMediaType
            $caps = New-Object byte[] $size
            for ($i = 0; $i -lt [Math]::Min($count, 12); $i++) {
                try {
                    $cfg.GetStreamCaps($i, $mt, $caps) | Out-Null
                    $w = 0; $h = 0
                    if ($mt.formatType -eq [DirectShowLib.FormatType]::VideoInfo -and $mt.pbFormat -ne [IntPtr]::Zero) {
                        $vi = [System.Runtime.InteropServices.Marshal]::PtrToStructure($mt.pbFormat, [type][DirectShowLib.VideoInfoHeader])
                        $w = $vi.bmiHeader.width; $h = $vi.bmiHeader.height
                    }
                    Write-Output ("    {0} {1}x{2}" -f (SubName $mt.subType), $w, $h)
                    [DirectShowLib.DsUtils]::FreeAMMediaType($mt)
                    $mt = New-Object DirectShowLib.AMMediaType
                } catch { Write-Output ("    caps#{0} error: {1}" -f $i, $_.Exception.Message); break }
            }
        }
    } finally {
        if ($pe -ne $null) { [System.Runtime.InteropServices.Marshal]::ReleaseComObject($pe) | Out-Null }
        [System.Runtime.InteropServices.Marshal]::ReleaseComObject($filter) | Out-Null
    }
}
