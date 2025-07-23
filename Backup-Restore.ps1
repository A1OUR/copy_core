# === Настройки ===
$driveLetter = "H"  # Буква тома, КУДА восстанавливаем
$backupFile = "F:\workfolder\copy_test\Резервная_копия_диска_H_20250723_144908.img"
$ddPath = "F:\workfolder\copy_core\dd.exe"  # Путь к dd.exe

# ========================================

# Проверка файлов
if (-not (Test-Path $ddPath)) {
    Write-Error "❌ Не найден dd.exe: $ddPath"
    Write-Host "Скачайте с: https://www.chrysocome.net/dd " -ForegroundColor Yellow
    pause
    exit 1
}
if (-not (Test-Path $backupFile)) {
    Write-Error "❌ Не найден файл бэкапа: $backupFile"
    pause
    exit 1
}

# Проверка тома
if (-not (Get-Partition | Where-Object DriveLetter -eq $driveLetter)) {
    Write-Error "❌ Том ${driveLetter}: не найден!"
    pause
    exit 1
}

# Подтверждение
Write-Warning "⚠️ ВНИМАНИЕ: Все данные на ${driveLetter}: будут БЕЗВОЗВРАТНО УНИЧТОЖЕНЫ!"
$confirm = Read-Host "Продолжить? (y/n)"
if ($confirm -notmatch "^y(es)?$") {
    Write-Host "Отменено пользователем." -ForegroundColor Yellow
    pause
    exit 0
}

# Путь к тому
$target = "\\.\${driveLetter}:"
$arguments = "of=`"$target`" if=`"$backupFile`" bs=1M --progress"

Write-Host "🔄 Восстановление: $backupFile → $target" -ForegroundColor Yellow
Write-Host "⏳ Ожидайте... Не закрывайте окно!" -ForegroundColor Gray

# Запуск dd и захват ExitCode
try {
    $process = Start-Process -FilePath $ddPath -ArgumentList $arguments -Wait -NoNewWindow -PassThru -ErrorAction Stop
    $exitCode = $process.ExitCode
}
catch {
    $exitCode = -1
    Write-Error "❌ Ошибка запуска dd.exe: $_"
}

# Анализ результата
if ($exitCode -eq 0) {
    Write-Host "✅ УСПЕХ! Том ${driveLetter}: успешно восстановлен." -ForegroundColor Green
} else {
    Write-Error "❌ Ошибка при восстановлении. Код выхода: $exitCode"
    
    # Частые коды ошибок
    switch ($exitCode) {
        1 { Write-Host "Код 1: Ошибка ввода/вывода (I/O). Возможно, диск занят или повреждён." }
        2 { Write-Host "Код 2: Ошибка синтаксиса или доступа. Проверьте права и путь." }
        3 { Write-Host "Код 3: Ошибка чтения входного файла (бэкап повреждён или не доступен)." }
        4 { Write-Host "Код 4: Ошибка записи. Нет доступа к $target, или диск защищён." }
        default { Write-Host "Неизвестная ошибка. Убедитесь, что флешка подключена и не извлечена." }
    }
    
    Write-Host ""
    Write-Warning "💡 Рекомендации:"
    Write-Host "   • Убедитесь, что флешка подключена"
    Write-Host "   • Закройте VeraCrypt, проводник, антивирус"
    Write-Host "   • Проверьте, что файл бэкапа не повреждён"
    Write-Host "   • Запустите PowerShell от имени АДМИНИСТРАТОРА"
}

pause