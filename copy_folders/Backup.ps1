[Console]::OutputEncoding = [System.Text.Encoding]::GetEncoding("windows-1251")
# Путь к конфигурационному файлу
$rootPath = Split-Path -Parent $MyInvocation.MyCommand.Definition
$scriptPath = $MyInvocation.MyCommand.Definition
$configFile = Join-Path $rootPath "config.txt"
$Lines = Get-Content $ConfigFile | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne "" -and $_ -notmatch '^\s*#' }

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

# Переменные для хранения значений
$SourceRoot = $null
$DestinationRoot = $null
$Folders = @()

$CurrentSection = $null

# Парсим файл построчно
foreach ($Line in $Lines) {
    if ($Line -match '^\[source\]$') {
        $CurrentSection = "source"
        continue
    }
    elseif ($Line -match '^\[destination\]$') {
        $CurrentSection = "destination"
        continue
    }
    elseif ($Line -match '^\[folders\]$') {
        $CurrentSection = "folders"
        continue
    }

    # Обработка содержимого в зависимости от секции
    switch ($CurrentSection) {
        "source" {
            if ($SourceRoot -eq $null) {
                $SourceRoot = $Line
            }
        }
        "destination" {
            if ($DestinationRoot -eq $null) {
                $DestinationRoot = $Line
            }
        }
        "folders" {
            $Folders += $Line
        }
    }
}

# Проверка обязательных полей
if (-not $SourceRoot) {
    Show-RetryDialog -Message "Не указан [source] в конфигурации."
    exit 1
}
if (-not $DestinationRoot) {
    Show-RetryDialog -Message "Не указан [destination] в конфигурации."
    exit 1
}
if ($Folders.Count -eq 0) {
    Show-RetryDialog -Message "Список [folders] пуст."
    exit 1
}

# Проверка существования исходной папки
if (-not (Test-Path $SourceRoot -PathType Container)) {
    Show-RetryDialog -Message "Исходная папка не существует: $SourceRoot"
    exit 1
}

# Проверка существования конечной папки
if (-not (Test-Path $DestinationRoot -PathType Container)) {
    Show-RetryDialog -Message "Конечная папка не существует: $DestinationRoot"
    exit 1
}

$DestinationRoot = Join-Path $DestinationRoot "Temp"
if (Test-Path $DestinationRoot -PathType Container) {
    Remove-Item $DestinationRoot -Force -Recurse
}

# Копируем каждую указанную папку

foreach ($FolderName in $Folders) {
    $SourcePath = Join-Path $SourceRoot $FolderName

    if (Test-Path $SourcePath -PathType Container) {
        #
    }
    else {
        Show-RetryDialog -Message "Папка не найдена: $SourcePath"
    }
}

# Имя файла
$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$outputFolderFinal = "Резервная_копия_${timestamp}"

foreach ($FolderName in $Folders) {
    $SourcePath = Join-Path $SourceRoot $FolderName

    if (Test-Path $SourcePath -PathType Container) {
        $DestinationPath = Join-Path $DestinationRoot $FolderName
        Write-Host "Копирование: $SourcePath → $DestinationPath"
        try {
            Copy-Item -Path $SourcePath -Destination $DestinationPath -Recurse -Force -Verbose -ErrorAction Stop
            Write-Host "Успешно: $FolderName" -ForegroundColor Green
        }
        catch {
            Show-RetryDialog -Message "Ошибка при копировании '$FolderName': $($_.Exception.Message)"
        }
    }
    else {
        Show-RetryDialog -Message "Папка не найдена: $SourcePath"
    }
}

Rename-Item -Path $DestinationRoot -NewName $outputFolderFinal

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