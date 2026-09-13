Add-Type -AssemblyName UIAutomationClient, UIAutomationTypes
$root = [System.Windows.Automation.AutomationElement]::RootElement

$p = Get-Process EasiCamera -ErrorAction SilentlyContinue | Select-Object -First 1
if (-not $p) { Write-Output 'no process'; exit 1 }
$win = $root.FindFirst([System.Windows.Automation.TreeScope]::Children,
    (New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::ProcessIdProperty, $p.Id)))
if (-not $win) { Write-Output 'no window element'; exit 1 }

# 找值含 OBS 的 ComboBox
$cbCond = New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::ControlTypeProperty, [System.Windows.Automation.ControlType]::ComboBox)
$cbs = $win.FindAll([System.Windows.Automation.TreeScope]::Descendants, $cbCond)
Write-Output ("combos: " + $cbs.Count)
$target = $null
foreach ($cb in $cbs) {
    $name = $cb.Current.Name
    Write-Output ("  combo: name='$name'")
}
$target = $cbs[0]
if (-not $target) { Write-Output 'target combo not found'; exit 1 }

$expand = $target.GetCurrentPattern([System.Windows.Automation.ExpandCollapsePattern]::Pattern)
$expand.Expand()
Start-Sleep -Milliseconds 1200

# 展开后枚举全桌面，找名字含 Bridge 的元素
$all = $root.FindAll([System.Windows.Automation.TreeScope]::Descendants, [System.Windows.Automation.Condition]::TrueCondition)
$hit = $null
foreach ($el in $all) {
    $n = $el.Current.Name
    if ($n -and $n -match 'EASI|Bridge') {
        Write-Output ("  found: '" + $n + "' ct=" + $el.Current.ControlType.ProgrammaticName + " cls=" + $el.Current.ClassName)
        if (-not $hit) { $hit = $el }
    }
}
if (-not $hit) { Write-Output 'item not found after expand'; exit 1 }
$patterns = $hit.GetSupportedPatterns()
foreach ($pt in $patterns) { Write-Output ("  pattern: " + $pt.ProgrammaticName) }
$sel = $null
foreach ($pt in $patterns) {
    if ($pt.ProgrammaticName -match 'SelectionItem') { $sel = $hit.GetCurrentPattern($pt) }
    elseif ($pt.ProgrammaticName -match 'Invoke') { $hit.GetCurrentPattern($pt).Invoke(); $sel = 'invoked'; break }
}
if ($sel -isnot [string]) { $sel.Select() }
Write-Output 'selected EASI-Bridge Camera'
Start-Sleep -Seconds 6

# 截图
Add-Type -AssemblyName System.Windows.Forms,System.Drawing
$b = New-Object System.Drawing.Bitmap([System.Windows.Forms.Screen]::PrimaryScreen.Bounds.Width, [System.Windows.Forms.Screen]::PrimaryScreen.Bounds.Height)
$g = [System.Drawing.Graphics]::FromImage($b)
$g.CopyFromScreen(0, 0, 0, 0, $b.Size)
$b.Save('D:\easi-connector\analysis\seewo-bridge.png')
$g.Dispose(); $b.Dispose()
Write-Output 'saved seewo-bridge.png'
