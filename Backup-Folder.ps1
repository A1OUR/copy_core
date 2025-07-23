# Настройка кодировки для текущей сессии
[Console]::OutputEncoding = [System.Text.Encoding]::GetEncoding("windows-1251")

# === Настройки ===
$rootPath = Split-Path -Parent $MyInvocation.MyCommand.Definition
$configPath = Join-Path $rootPath "config.json"
$config = Get-Content -Path $configPath -Raw | ConvertFrom-Json

$driveLetter = $config.driveLetter
$backupFolder = $config.backupFolder
$blockSize = $config.blockSize
$ddPath = $config.ddPath

$backupScriptName = $config.backupScriptName
$scriptPath = Join-Path $rootPath $backupScriptName

# ========================================
# ========================================
# Функция: Показать окно "Идёт копирование"
# ========================================

Add-Type -AssemblyName System.Windows.Forms

# Создаём форму
$form = New-Object System.Windows.Forms.Form
$form.Text = "Выполнение копирования"
$form.Size = New-Object System.Drawing.Size(350, 150)
$form.StartPosition = "CenterScreen"  # Окно по центру экрана
$form.FormBorderStyle = 'FixedSingle' # Фиксированный размер
$form.MaximizeBox = $false            # Без кнопки максимизации

# Добавляем метку (подпись)
$label = New-Object System.Windows.Forms.Label
$label.Text = "Производится резервное копирование, пожалуйста не монтируйте и не извлекайте диск"
$label.Location = New-Object System.Drawing.Point(30, 40)
$label.Size = New-Object System.Drawing.Size(300, 23)
$form.Controls.Add($label)

# Показываем форму
$form.Show()

trap {
    $form.Close()
    exit 1
}

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

# Создаём папку
if (-not (Test-Path $backupFolder)) {
    New-Item -ItemType Directory -Path $backupFolder -Force | Out-Null
}

# Имя файла
$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$outputFile = Join-Path $backupFolder "Резервная_копия_диска_${driveLetter}_${timestamp}.img"

# Команда
$source = "\\.\${driveLetter}:"
$arguments = "if=`"$source`" of=`"$outputFile`" bs=${blockSize} --progress"

# Запуск

Start-Process -FilePath $ddPath -ArgumentList $arguments -Wait -NoNewWindow
if (Test-Path $outputFile) {
    Write-Host "Файл существует"
} else {
    Write-Host "Файл не найден"
	Show-RetryDialog -Message "Не удалось сделать резервную копию диска ${driveLetter}, убедитесь, что диск не смонтирован в TrueCrypt"
	exit 1
}