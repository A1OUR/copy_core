# Настройка кодировки для текущей сессии
[Console]::OutputEncoding = [System.Text.Encoding]::GetEncoding("windows-1251")

# === Настройки ===
$rootPath = Split-Path -Parent $MyInvocation.MyCommand.Definition
$configPath = Join-Path $rootPath "config.json"
$config = Get-Content -Path $configPath -Raw | ConvertFrom-Json

$driveLetter = $config.driveLetter
$backupFolder = $config.backupFolder
$blockSize = $config.blockSize
$ddPath = Join-Path $rootPath "dd.exe"

$backupScriptName = $config.backupScriptName
$scriptPath = $MyInvocation.MyCommand.Definition

# Функция: Показать окно с кнопкой "Повторить"
function Show-RetryDialog {
    param(
        [string]$Message = "Произошла ошибка при выполнении резервного копирования."
    )
	$form.Close()
    Add-Type -AssemblyName System.Windows.Forms

    $form = New-Object System.Windows.Forms.Form
    $form.Text = "Ошибка резервного копирования"
    $form.Size = New-Object System.Drawing.Size(400, 180)
    $form.StartPosition = "CenterScreen"
    $form.FormBorderStyle = "FixedDialog"
    $form.TopMost = $true
    $form.MaximizeBox = $false
    $form.MinimizeBox = $false

    $label = New-Object System.Windows.Forms.Label
    $label.Location = New-Object System.Drawing.Point(20, 20)
    $label.Size = New-Object System.Drawing.Size(350, 40)
    $label.Text = $Message
    $form.Controls.Add($label)

    $buttonRetry = New-Object System.Windows.Forms.Button
    $buttonRetry.Location = New-Object System.Drawing.Point(120, 70)
    $buttonRetry.Size = New-Object System.Drawing.Size(100, 30)
    $buttonRetry.Text = "Повторить"
    $buttonRetry.DialogResult = [System.Windows.Forms.DialogResult]::Retry
    $form.Controls.Add($buttonRetry)

    $buttonExit = New-Object System.Windows.Forms.Button
    $buttonExit.Location = New-Object System.Drawing.Point(230, 70)
    $buttonExit.Size = New-Object System.Drawing.Size(100, 30)
    $buttonExit.Text = "Выход"
    $buttonExit.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
    $form.Controls.Add($buttonExit)

    $form.AcceptButton = $buttonRetry
    $form.CancelButton = $buttonExit

    $result = $form.ShowDialog()

    if ($result -eq [System.Windows.Forms.DialogResult]::Retry) {
        # Перезапускаем текущий скрипт
        & powershell -ExecutionPolicy Bypass -File "`"$scriptPath`""
        exit 0
    } else {
        exit 1
    }
}


# Проверка dd.exe
if (-not (Test-Path $ddPath)) {
    Show-RetryDialog -Message "Не найден dd.exe: $ddPath"
    exit 1
}

# Проверка, существует ли H:
if (-not (Get-Partition | Where-Object DriveLetter -eq $driveLetter)) {
    Show-RetryDialog -Message "Не удалось подключить том ${driveLetter}:. Убедитесь, что диск вставлен"
    exit 1
}

# ========================================
# Показать окно "Идёт копирование"
# ========================================

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# Создаём форму
$form = New-Object System.Windows.Forms.Form
$form.Text = "Выполнение копирования"
$form.Size = New-Object System.Drawing.Size(400, 150)
$form.StartPosition = "CenterScreen"  # Окно по центру экрана
$form.FormBorderStyle = "FixedDialog"
$form.MaximizeBox = $false            # Без кнопки максимизации

# Добавляем метку (подпись)
$label = New-Object System.Windows.Forms.Label
$label.Text = "Производится резервное копирование, пожалуйста не монтируйте и не извлекайте диск"
$label.Location = New-Object System.Drawing.Point(30, 20)
$label.Size = New-Object System.Drawing.Size(300, 30)
$form.Controls.Add($label)

# Прогресс-бар
$progressBar = New-Object System.Windows.Forms.ProgressBar
$progressBar.Location = New-Object System.Drawing.Point(20, 70)
$progressBar.Size = New-Object System.Drawing.Size(340, 30)
$progressBar.Minimum = 0
$progressBar.Maximum = 100
$progressBar.Value = 0
$progressBar.Step = 1
$form.Controls.Add($progressBar)

# Показываем форму
$form.Show()
$form.Refresh()

trap {
    if ($form){
        $form.Close()
    }
}


# Получить размер диска
try {
    $partition = Get-Partition -DriveLetter $driveLetter
	if (-not $partition) {
        throw "Раздел с буквой диска $driveLetter не найден."
    }
    $diskSize = $partition.Size
    $diskSizeMB = [math]::Round($diskSize / 1MB)
}
catch {
    Show-RetryDialog -Message "Не удалось подключить том ${driveLetter}:. Убедитесь, что диск вставлен"
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
$arguments = "if=`"$source`" of=`"$outputFile`" bs=${blockSize}M --progress"

# === ЗАПУСК DD С КОНТРОЛЕМ ПРОГРЕССА ===
$psi = New-Object System.Diagnostics.ProcessStartInfo
$psi.FileName = $ddPath
$psi.Arguments = $arguments
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
            $percent = [Math]::Min(100, [Math]::Floor(($processedBytes / $diskSizeMB) * 100))
			if ($percent -gt 100) {
				$progressBar.Value = 100
			}
			else {
            $progressBar.Value = $percent
            $form.Refresh()
			}
        }
    }
}

# Дожидаемся завершения
$process.WaitForExit()

# Теперь можно получить код выхода
$exitCode = $process.ExitCode

if (Test-Path $outputFile) {
	# Получаем размер образа
	$imageSize = (Get-Item $outputFile).Length

	# Сравнение
	if ($exitCode -ne 0)
	{
		if ($imageSize -ne $diskSize) {
			Remove-Item $outputFile -Force
			Show-RetryDialog -Message "Размер резервной копии не совпадает с размером диска, возможно диск был отключён во время копирования или закончилось место для резервных копий"
			exit 1
		}
	}
	if (-not (Get-Partition | Where-Object DriveLetter -eq $driveLetter)) {
		Remove-Item $outputFile -Force
		Show-RetryDialog -Message "Диск ${driveLetter}: был отключён во время копирования. Не отключайте и не монтируйте диск во время копирования."
		exit 1
	}
	$progressBar.Value = 100
	$form.Close()
	Write-Host "Файл существует"
	# Подключаем библиотеки
	Add-Type -AssemblyName System.Windows.Forms
	Add-Type -AssemblyName System.Drawing

	# Создаём форму
	$form2 = New-Object System.Windows.Forms.Form
	$form2.Text = "Информация"
	$form2.Size = New-Object System.Drawing.Size(300, 150)
	$form2.StartPosition = "CenterScreen"
	$form2.TopMost = $true
	$form2.FormBorderStyle = "FixedDialog"  # Нельзя изменять размер
	$form2.MaximizeBox = $false
	$form2.MinimizeBox = $false

	# Метка (текст)
	$label2 = New-Object System.Windows.Forms.Label
	$label2.Location = New-Object System.Drawing.Point(30, 30)
	$label2.Size = New-Object System.Drawing.Size(250, 40)
	$label2.Text = "Резервное копирование завершено"
	$form2.Controls.Add($label2)

	# Кнопка "ОК"
	$buttonOK = New-Object System.Windows.Forms.Button
	$buttonOK.Location = New-Object System.Drawing.Point(100, 80)
	$buttonOK.Size = New-Object System.Drawing.Size(100, 30)
	$buttonOK.Text = "ОК"
	$buttonOK.DialogResult = [System.Windows.Forms.DialogResult]::OK
	$form2.AcceptButton = $buttonOK  # Нажатие Enter = ОК

	# Добавляем кнопку в форму
	$form2.Controls.Add($buttonOK)

	# Показываем окно и ждём нажатия
	$form2.ShowDialog() | Out-Null
} else {
    Write-Host "Файл не найден"
	Show-RetryDialog -Message "Не удалось сделать резервную копию диска ${driveLetter}, убедитесь, что диск не смонтирован в TrueCrypt"
	exit 1
}