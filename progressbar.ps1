# Подключаем Windows Forms
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# === НАСТРОЙКИ ===
$ddPath = "F:\workfolder\copy_core\dd.exe"  # Путь к dd.exe
$driveLetter = "H"
$inputDevice = "\\.\${driveLetter}:"   # ⚠️ Внимание: Укажите правильный диск (например, \\.\PhysicalDrive1)
$outputFile = "F:\workfolder\copy_test\backup.img"         # Куда сохранять образ
$blockSize = "1M"

# Вычисляем примерный общий размер в байтах
$partition = Get-Partition -DriveLetter $driveLetter
$totalBytes = $partition.Size
$bytesPerBlock = 4 * 1MB  # Соответствует 4M

# === СОЗДАНИЕ ОКНА ===
$form = New-Object System.Windows.Forms.Form
$form.Text = "Копирование диска..."
$form.Size = New-Object System.Drawing.Size(400, 150)
$form.StartPosition = "CenterScreen"
$form.FormBorderStyle = 'FixedSingle'
$form.MaximizeBox = $false
$form.TopMost = $true
# Метка состояния
$label = New-Object System.Windows.Forms.Label
$label.Location = New-Object System.Drawing.Point(20, 20)
$label.Size = New-Object System.Drawing.Size(350, 23)
$label.Text = "Начинаем копирование..."
$form.Controls.Add($label)

# Прогресс-бар
$progressBar = New-Object System.Windows.Forms.ProgressBar
$progressBar.Location = New-Object System.Drawing.Point(20, 50)
$progressBar.Size = New-Object System.Drawing.Size(340, 30)
$progressBar.Minimum = 0
$progressBar.Maximum = 100
$progressBar.Value = 0
$progressBar.Step = 1
$form.Controls.Add($progressBar)

# Показываем форму
$form.Show()
$form.Refresh()

# === ЗАПУСК DD С КОНТРОЛЕМ ПРОГРЕССА ===
$psi = New-Object System.Diagnostics.ProcessStartInfo
$psi.FileName = $ddPath
$psi.Arguments = "if=$inputDevice of=$outputFile bs=$blockSize --progress"
$psi.UseShellExecute = $false
$psi.RedirectStandardOutput = $true
$psi.RedirectStandardError = $true
$psi.CreateNoWindow = $true

$process = New-Object System.Diagnostics.Process
$process.StartInfo = $psi
$process.Start() | Out-Null
$process.PriorityClass = "Idle"  # Чтобы не нагружать систему

# Переменная для отслеживания обработанных байтов
$processedBytes = 0

# Читаем stderr (там выводится прогресс от dd)
while (!$process.StandardError.EndOfStream) {
    $line = $process.StandardError.ReadLine()
    if ($line) {
        if ($line -match '(\d+)M') {
            $captured = $matches[1]
            $processedBytes = [long]$captured

            # Обновляем прогресс-бар
            $percent = [Math]::Min(100, [Math]::Floor(($processedBytes / 100) * 100))
            $progressBar.Value = $percent


            $form.Text = $percent
            $form.Refresh()
        }
    }
}

# Дожидаемся завершения
$process.WaitForExit()

# Завершаем
if ($process.ExitCode -eq 0) {
    $label.Text = "Готово! Образ сохранён в $outputFile"
} else {
    $label.Text = "Ошибка! Код выхода: $($process.ExitCode)"
}