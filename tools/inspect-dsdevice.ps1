$a = [System.Reflection.Assembly]::LoadFrom('D:\easi-connector\easi-soft\EasiCamera_2.1.0.4410\Main\DirectShowLib.dll')
$t = $a.GetType('DirectShowLib.DsDevice')
Write-Output '--- all ctors ---'
$t.GetConstructors([System.Reflection.BindingFlags]'Public,NonPublic,Instance') | ForEach-Object { $_.ToString() }
Write-Output '--- properties ---'
$t.GetProperties() | Select-Object -First 10 | ForEach-Object { $_.ToString() }
