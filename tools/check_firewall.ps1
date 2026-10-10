$ports = '3000','3002','3003','3004','7357'
Get-NetFirewallPortFilter -ErrorAction SilentlyContinue |
  Where-Object { $_.LocalPort -in $ports } |
  ForEach-Object {
    $rule = $_ | Get-NetFirewallRule -ErrorAction SilentlyContinue
    if ($rule -and $rule.Direction -eq 'Inbound' -and $rule.Action -eq 'Allow') {
      Write-Output ("ALLOW port " + $_.LocalPort + " | " + $rule.DisplayName + " | enabled=" + $rule.Enabled)
    }
  }
Get-NetFirewallApplicationFilter -ErrorAction SilentlyContinue |
  Where-Object { $_.Program -like '*dart*' } |
  ForEach-Object {
    $r = $_ | Get-NetFirewallRule -ErrorAction SilentlyContinue
    if ($r -and $r.Direction -eq 'Inbound') {
      Write-Output ("DART rule: " + $r.DisplayName + " | action=" + $r.Action + " | enabled=" + $r.Enabled)
    }
  }
Write-Output "CHECK_DONE"
