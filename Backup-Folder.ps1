# Настройка кодировки для текущей сессии
[Console]::OutputEncoding = [System.Text.Encoding]::GetEncoding("windows-1251")

# === Настройки ===
$driveLetter = "H"
$backupFolder = "F:\workfolder\copy_test"
$ddPath = "F:\workfolder\copy_core\dd.exe" 

# ========================================

# Проверка dd.exe
if (-not (Test-Path $ddPath)) {
    Write-Error "Не найден dd.exe: $ddPath"
    pause
    exit 1
}

# Проверка, существует ли H:
if (-not (Get-Partition | Where-Object DriveLetter -eq $driveLetter)) {
    Write-Error "Том ${driveLetter}: не найден!"
    pause
    exit 1
}

# Создаём папку
if (-not (Test-Path $backupFolder)) {
    New-Item -ItemType Directory -Path $backupFolder -Force | Out-Null
}

# Имя файла
$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$outputFile = Join-Path $backupFolder "Резервная_копия_диска_${driveLetter}_${timestamp}.img"

# Команда
$source = "\\.\${driveLetter}:"
$arguments = "if=`"$source`" of=`"$outputFile`" bs=1M --progress"

# Запуск
Start-Process -FilePath $ddPath -ArgumentList $arguments -Wait -NoNewWindow

# Проверка результата
if (Test-Path $outputFile) {
    $sizeMB = [math]::Round((Get-Item $outputFile).Length / 1MB, 1)
    Write-Host "✅ Успех! Создан образ зашифрованного тома:" -ForegroundColor Green
    Write-Host "    Размер: $sizeMB МБ" -ForegroundColor Green
    Write-Host "    Файл: $outputFile" -ForegroundColor Green
} else {
    Write-Error "❌ Ошибка: файл не создан"
}

pause