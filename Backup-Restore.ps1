# Настройка кодировки для текущей сессии
Clear-Host
Write-Host "Идёт подготовка к восстановлению резервной копии, подождите"
[Console]::OutputEncoding = [System.Text.Encoding]::GetEncoding("windows-1251")
# Отключаем кнопку "Закрыть" (крестик) в заголовке окна
Function _Disable-X {
    #Calling user32.dll methods for Windows and Menus
    $MethodsCall = '
    [DllImport("user32.dll")] public static extern long GetSystemMenu(IntPtr hWnd, bool bRevert);
    [DllImport("user32.dll")] public static extern bool EnableMenuItem(long hMenuItem, long wIDEnableItem, long wEnable);
    [DllImport("user32.dll")] public static extern long SetWindowLongPtr(long hWnd, long nIndex, long dwNewLong);
    [DllImport("user32.dll")] public static extern bool EnableWindow(long hWnd, int bEnable);
    '

    $SC_CLOSE = 0xF060
    $MF_DISABLED = 0x00000002L


    #Create a new namespace for the Methods to be able to call them
    Add-Type -MemberDefinition $MethodsCall -name NativeMethods -namespace Win32

    $PSWindow = Get-Process -Pid $PID
    $hwnd = $PSWindow.MainWindowHandle

    #Get System menu of windows handled
    $hMenu = [Win32.NativeMethods]::GetSystemMenu($hwnd, 0)

    #Disable X Button
    [Win32.NativeMethods]::EnableMenuItem($hMenu, $SC_CLOSE, $MF_DISABLED) | Out-Null
	
}

_Disable-X


# === Настройки ===
$rootPath = Split-Path -Parent $MyInvocation.MyCommand.Definition
$configPath = Join-Path $rootPath "config.json"
$config = Get-Content -Path $configPath -Raw | ConvertFrom-Json

$driveLetter = $config.driveLetter
$backupFolder = $config.backupFolder
$blockSize = $config.blockSize
$ddPath = Join-Path $rootPath "dd.exe"

$scriptPath = $MyInvocation.MyCommand.Definition


# Функция: Показать окно с кнопкой "Повторить"
function Show-RetryDialog {
    param(
        [string]$Message = "Произошла ошибка при выполнении восстановления."
    )
    Add-Type -AssemblyName System.Windows.Forms

    $form = New-Object System.Windows.Forms.Form
    $form.Text = "Ошибка восстановления резервной копии"
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

# Проверка не запущено ли резервное копирование
$process = Get-Process -Name "dd" -ErrorAction SilentlyContinue
if ($process) {
	Show-RetryDialog -Message "Во время восстановления резервной копии резервное копирование невозможно."
    exit 1
}

# Проверка dd.exe
if (-not (Test-Path $ddPath)) {
    Show-RetryDialog -Message "Не найден dd.exe: $ddPath"
    exit 1
}

# Проверка наличия диска

try {
    $partition = Get-Partition -DriveLetter $driveLetter -ErrorAction Stop
	if (-not $partition) {
        throw "Раздел с буквой диска $driveLetter не найден."
	}
}
catch {
	Show-RetryDialog -Message "Не удалось подключить том ${driveLetter}:. Убедитесь, что диск вставлен."
    exit 1
}

if (-not (Test-Path $backupFolder)) {
    New-Item -ItemType Directory -Path $backupFolder -Force | Out-Null
}

Add-Type -AssemblyName System.Windows.Forms

# Создаем объект OpenFileDialog
$openFileDialog = New-Object System.Windows.Forms.OpenFileDialog
$openFileDialog.Title = "Выберите резервную копию для восстановления"
$openFileDialog.Filter = "IMG файлы (*.img)|*.img"

# Устанавливаем путь по умолчанию
$openFileDialog.InitialDirectory = $backupFolder

# Открываем диалоговое окно
$result = $openFileDialog.ShowDialog()

# Если пользователь нажал "ОК"
if ($result -eq 'OK') {
    # Сохраняем путь к файлу в переменную
    $selectedFilePath = $openFileDialog.FileName
    Write-Host "Выбранный файл: $selectedFilePath"
} else {
    exit 0
}

$fileName = [System.IO.Path]::GetFileName($selectedFilePath)

$form = New-Object System.Windows.Forms.Form
$form.Text = "Подтверждение копирования"
$form.Size = New-Object System.Drawing.Size(400, 220)
$form.StartPosition = "CenterScreen"
$form.FormBorderStyle = "FixedDialog"
$form.TopMost = $true
$form.MaximizeBox = $false
$form.MinimizeBox = $false

$label = New-Object System.Windows.Forms.Label
$label.Location = New-Object System.Drawing.Point(20, 20)
$label.Size = New-Object System.Drawing.Size(350, 60)
$label.Text = "Для восстановления выбран файл: `n${fileName}`n`nПродолжить?"
$form.Controls.Add($label)

$buttonYes = New-Object System.Windows.Forms.Button
$buttonYes.Location = New-Object System.Drawing.Point(20, 90)
$buttonYes.Size = New-Object System.Drawing.Size(100, 30)
$buttonYes.Text = "Да"
$buttonYes.DialogResult = [System.Windows.Forms.DialogResult]::OK
$form.Controls.Add($buttonYes)

$buttonChooseAnother = New-Object System.Windows.Forms.Button
$buttonChooseAnother.Location = New-Object System.Drawing.Point(130, 90)
$buttonChooseAnother.Size = New-Object System.Drawing.Size(130, 30)
$buttonChooseAnother.Text = "Выбрать другой файл"
$buttonChooseAnother.DialogResult = [System.Windows.Forms.DialogResult]::Retry
$form.Controls.Add($buttonChooseAnother)

$buttonExit = New-Object System.Windows.Forms.Button
$buttonExit.Location = New-Object System.Drawing.Point(270, 90)
$buttonExit.Size = New-Object System.Drawing.Size(100, 30)
$buttonExit.Text = "Отмена"
$buttonExit.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
$form.Controls.Add($buttonExit)

$form.AcceptButton = $buttonYes
$form.CancelButton = $buttonExit

$result = $form.ShowDialog()

if ($result -eq [System.Windows.Forms.DialogResult]::OK) {
	; # Продолжение
} elseif ($result -eq [System.Windows.Forms.DialogResult]::Retry) {
    # Перезапускаем текущий скрипт
    & powershell -ExecutionPolicy Bypass -File "`"$scriptPath`""
    exit 0
} else {
    exit 1
}



$form = New-Object System.Windows.Forms.Form
$form.Text = "Подтверждение копирования"
$form.Size = New-Object System.Drawing.Size(400, 220)
$form.StartPosition = "CenterScreen"
$form.FormBorderStyle = "FixedDialog"
$form.TopMost = $true
$form.MaximizeBox = $false
$form.MinimizeBox = $false

$label = New-Object System.Windows.Forms.Label
$label.Location = New-Object System.Drawing.Point(20, 20)
$label.Size = New-Object System.Drawing.Size(350, 60)
$label.Text = "ВНИМАНИЕ: Все данные на ${driveLetter}: будут БЕЗВОЗВРАТНО УНИЧТОЖЕНЫ!`n`nПродолжить?"
$form.Controls.Add($label)

$buttonYes = New-Object System.Windows.Forms.Button
$buttonYes.Location = New-Object System.Drawing.Point(20, 90)
$buttonYes.Size = New-Object System.Drawing.Size(100, 30)
$buttonYes.Text = "Да"
$buttonYes.DialogResult = [System.Windows.Forms.DialogResult]::OK
$form.Controls.Add($buttonYes)

$buttonExit = New-Object System.Windows.Forms.Button
$buttonExit.Location = New-Object System.Drawing.Point(270, 90)
$buttonExit.Size = New-Object System.Drawing.Size(100, 30)
$buttonExit.Text = "Отмена"
$buttonExit.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
$form.Controls.Add($buttonExit)

$form.AcceptButton = $buttonYes
$form.CancelButton = $buttonExit

$result = $form.ShowDialog()

if ($result -eq [System.Windows.Forms.DialogResult]::OK) {
    ; # Продолжение
} else {
    exit 1
}


# ========================================
# Показать окно "Идёт копирование"
# ========================================
Write-Host "НЕ ЗАКРЫВАЙТЕ ЭТО ОКНО ПОКА ИДЁТ ВОССТАНОВЛЕНИЕ РЕЗЕРВНОЙ КОПИИ"
Write-Host "Для отмены восстановления нажмите Ctrl+C в этом окне"
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# Глобальная переменная для отслеживания отмены
$Global:CancelBackup = $false

# Создаём форму
$form = New-Object System.Windows.Forms.Form
$form.Text = "Выполнение восстановления"
$form.Size = New-Object System.Drawing.Size(450, 180)
$form.StartPosition = "CenterScreen"
$form.FormBorderStyle = "FixedDialog"
$form.MaximizeBox = $false
$form.MinimizeBox = $false
$form.TopMost = $true  # Поверх всех окон
$form.ControlBox = $false
# Метка
$label = New-Object System.Windows.Forms.Label
$label.Text = "Производится восстановление резервной копии, пожалуйста, не извлекайте диск"
$label.Location = New-Object System.Drawing.Point(20, 20)
$label.Size = New-Object System.Drawing.Size(400, 30)
$form.Controls.Add($label)

# Прогресс-бар
$progressBar = New-Object System.Windows.Forms.ProgressBar
$progressBar.Location = New-Object System.Drawing.Point(20, 60)
$progressBar.Size = New-Object System.Drawing.Size(400, 30)
$progressBar.Minimum = 0
$progressBar.Maximum = 100
$progressBar.Value = 0
$form.Controls.Add($progressBar)


# Показываем форму
$form.Show()
# Ловим Ctrl+C или закрытие окна
trap {
    $Global:CancelBackup = $true
    if ($process -and !$process.HasExited) {
        $process.Kill()
    }
    if ($form) { $form.Close() }
}

# Путь к тому
$target = "\\.\${driveLetter}:"

# === ЗАПУСК DD С КОНТРОЛЕМ ПРОГРЕССА И ОТМЕНОЙ ===
$psi = New-Object System.Diagnostics.ProcessStartInfo
$psi.FileName = $ddPath
$psi.Arguments = "of=`"$target`" if=`"$selectedFilePath`" bs=${blockSize}M --progress"
$psi.UseShellExecute = $false
$psi.RedirectStandardOutput = $true
$psi.RedirectStandardError = $true
$psi.CreateNoWindow = $true

$process = New-Object System.Diagnostics.Process
$process.StartInfo = $psi
$process.Start() | Out-Null
$process.PriorityClass = "Idle"

# Переменная для отслеживания прогресса
$processedMB = 0
$imageSize = [Math]::Round((Get-Item $selectedFilePath).Length / 1MB)


# Читаем stderr построчно (там выводится прогресс)
while (!$process.StandardError.EndOfStream) {

    $line = $process.StandardError.ReadLine().Replace(",", "")
    if ($line -match '(\d+)M') {
        $processedMB = [int]$matches[1]
        $percent = [Math]::Min(100, [Math]::Floor($processedMB / $imageSize * 100))
        $progressBar.Value = $percent
    }
	$form.Refresh()
	[System.Windows.Forms.Application]::DoEvents()
}

$process.WaitForExit()
$exitCode = $process.ExitCode
$form.Close()

if ($line -match 'Error opening output file') {
	Show-RetryDialog -Message "Не удалось сделать восстановить резервную копию диска ${driveLetter}, убедитесь, что диск вставлен, не смонтирован в TrueCrypt и в данный момент не производится резервное копирование"
	exit 1
}
if (-not (Get-Partition | Where-Object DriveLetter -eq $driveLetter)) {
	Show-RetryDialog -Message "Диск ${driveLetter}: был отключён во время восстановления. Не отключайте и не монтируйте диск во время восстановления."
	exit 1
}

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
$label2.Text = "Восстановление резервной копии завершено"
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