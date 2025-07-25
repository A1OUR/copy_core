# Настройка кодировки для текущей сессии
Clear-Host
Write-Host "Идёт подготовка к резервному копированию, подождите"
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

$backupScriptName = $config.backupScriptName
$scriptPath = $MyInvocation.MyCommand.Definition
$outputFile = Join-Path $backupFolder "Temp.img"


# Функция: Показать окно с кнопкой "Повторить"
function Show-RetryDialog {
    param(
        [string]$Message = "Произошла ошибка при выполнении резервного копирования."
    )
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

# Уборка мусора после предыдущего копирования
<# $process = Get-Process -Name "dd" -ErrorAction SilentlyContinue
if ($process) {
	Start-Sleep -Seconds 1
	Show-RetryDialog -Message "Отмена копирования. Не запускайте следующее копирование пока не было завершено предыдущее."
	exit 1
}

if (Test-Path $outputFile) {
	Remove-Item $outputFile -Force
} #>

# Проверка dd.exe
if (-not (Test-Path $ddPath)) {
    Show-RetryDialog -Message "Не найден dd.exe: $ddPath"
    exit 1
}


# Получить размер диска
try {
    $partition = Get-Partition -DriveLetter $driveLetter -ErrorAction Stop
	if (-not $partition) {
        throw "Раздел с буквой диска $driveLetter не найден."
	}
    $diskSize = $partition.Size
    $diskSizeMB = [Math]::Round($diskSize / 1MB)

    Write-Host "Размер диска ${driveLetter}: составляет ${diskSizeMB} МБ"

    # Проверка: хватит ли места для сохранения файла образа
    $outputDir = Split-Path -Path $outputFile -Parent

    # Получаем диск, на котором будет сохраняться файл
    $outputDriveLetter = (Get-Item $outputDir).PSDrive.Name
    $outputPSDrive = Get-PSDrive -Name $outputDriveLetter -PSProvider FileSystem -ErrorAction Stop
    $freeSpace = $outputPSDrive.Free

    if ($freeSpace -lt $diskSize) {
        $requiredMB = [Math]::Round($diskSize / 1MB)
        $availableMB = [Math]::Round($freeSpace / 1MB)
        Show-RetryDialog -Message "Недостаточно места для сохранения образа. Требуется ${requiredMB} МБ, но на диске ${outputDriveLetter}: свободно только ${availableMB} МБ."
        exit 1
    }
}
catch {
	Show-RetryDialog -Message "Не удалось подключить том ${driveLetter}:. Убедитесь, что диск вставлен."
    exit 1
}

# ========================================
# Показать окно "Идёт копирование"
# ========================================
Write-Host "НЕ ЗАКРЫВАЙТЕ ЭТО ОКНО ПОКА ИДЁТ КОПИРОВАНИЕ"
Write-Host "Для отмены копирования нажмите Ctrl+C в этом окне"
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# Глобальная переменная для отслеживания отмены
$Global:CancelBackup = $false

# Создаём форму
$form = New-Object System.Windows.Forms.Form
$form.Text = "Выполнение копирования"
$form.Size = New-Object System.Drawing.Size(450, 180)
$form.StartPosition = "CenterScreen"
$form.FormBorderStyle = "FixedDialog"
$form.MaximizeBox = $false
$form.MinimizeBox = $false
$form.TopMost = $true  # Поверх всех окон
$form.ControlBox = $false
# Метка
$label = New-Object System.Windows.Forms.Label
$label.Text = "Производится резервное копирование, пожалуйста, не извлекайте диск"
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

# Создаём папку
if (-not (Test-Path $backupFolder)) {
    New-Item -ItemType Directory -Path $backupFolder -Force | Out-Null
}

# Имя файла
$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$outputFileFinal = Join-Path $backupFolder "Резервная_копия_диска_${driveLetter}_${timestamp}.img"

# === ЗАПУСК DD С КОНТРОЛЕМ ПРОГРЕССА И ОТМЕНОЙ ===
$psi = New-Object System.Diagnostics.ProcessStartInfo
$psi.FileName = $ddPath
$psi.Arguments = "if=\\.\${driveLetter}: of=`"$outputFile`" bs=${blockSize}M --progress"
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

# Читаем stderr построчно (там выводится прогресс)
while (!$process.StandardError.EndOfStream) {

    $line = $process.StandardError.ReadLine()
    if ($line -match '(\d+)M') {
        $processedMB = [int]$matches[1]
        $percent = [Math]::Min(100, [Math]::Floor(($processedMB * 1MB) / $diskSize * 100))
        $progressBar.Value = $percent
        $form.Refresh()
    }
}

$process.WaitForExit()  # Ждём 2 секунды

# Завершаем
$exitCode = $process.ExitCode
$form.Close()

if (Test-Path $outputFile) {
	# Получаем размер образа
	$imageSize = (Get-Item $outputFile).Length

	# Сравнение
	if ($exitCode -ne 0)
	{
		if ($imageSize -ne $diskSize) {
			Remove-Item $outputFile -Force
			exit 1
		}
	}
	if (-not (Get-Partition | Where-Object DriveLetter -eq $driveLetter)) {
		Remove-Item $outputFile -Force
		Show-RetryDialog -Message "Диск ${driveLetter}: был отключён во время копирования. Не отключайте и не монтируйте диск во время копирования."
		exit 1
	}
	$progressBar.Value = 100
	Rename-Item -Path $outputFile -NewName (Split-Path $outputFileFinal -Leaf)
	Write-Host "Резервная копия создана"
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
    Write-Host "Резервная копия не создана"
	Show-RetryDialog -Message "Не удалось сделать резервную копию диска ${driveLetter}, убедитесь, что диск вставлен и не смонтирован в TrueCrypt"
	exit 1
}