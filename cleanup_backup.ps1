# === Настройки ===
$rootPath = Split-Path -Parent $MyInvocation.MyCommand.Definition
$configPath = Join-Path $rootPath "config.json"
$config = Get-Content -Path $configPath -Raw | ConvertFrom-Json
$backupFolder = $config.backupFolder
$outputFile = Join-Path $backupFolder "Temp.img"

# Остановка dd.exe по имени
if (Test-Path $outputFile) {
	$process = Get-Process -Name "dd" -ErrorAction SilentlyContinue
	if ($process) {
		$process | Stop-Process -Force
		Start-Sleep -Seconds 1
	}
}

if (Test-Path $outputFile) {
	Remove-Item $outputFile -Force
}