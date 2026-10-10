Get-CimInstance Win32_Process -Filter "Name='chrome.exe'" |
  Where-Object { $_.CommandLine -match 'remote-debugging-port' -and $_.CommandLine -notmatch '--type=' } |
  ForEach-Object {
    if ($_.CommandLine -match 'remote-debugging-port=(\d+)') {
      Write-Output ("port=" + $Matches[1] + " pid=" + $_.ProcessId + " profile=" + ($(if ($_.CommandLine -match 'user-data-dir=([^\s]+)') { $Matches[1] })))
    }
  }
