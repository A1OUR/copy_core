Add-Type -AssemblyName System.Windows.Forms

# Parameters
$activity = 'Running...'
$totalMinutes = 0.15      # How many minutes to run in total
$timerIntervalSecs = 0.1  # The timer-event firing interval
$timer = [System.Timers.Timer]::new($timerIntervalSecs * 1000) # create the timer

# A data-transfer object used for communicating with 
# the -Action script block below.
$dto = @{ 
  Activity = $activity
  EndTime = (Get-Date).AddMinutes($totalMinutes)
  TotalMinutes = $totalMinutes
  Done = $false # will be set to $true when the progress bar has reached 100% or the form was closed manually.
  AbortedAt = $null # if the form was closed manually, will be set to the percent-complete value at that time.
  Form = $null # will be filled in the -Action script block to store the form object between invocations.
}

# Register a script block as the delegate for the timer's "Elapsed" event
# (-Action parameter).
# The data-transfer object is passed via the -MessageData parameter.
$eventJob = Register-ObjectEvent -InputObject $timer -EventName Elapsed -Action { 
  $endTime, $totalMinutes, $activity, $form = $Event.MessageData.EndTime, $Event.MessageData.TotalMinutes, $Event.MessageData.Activity, $Event.MessageData.Form
  # Create the form on demand.
  if (-not $form) {
    $form = $Event.MessageData.Form = [System.Windows.Forms.Form] @{ TopMost = $true; Text = $activity; MinimizeBox = $false; MaximizeBox = $false; Width = 290; Height = 100; StartPosition = 'CenterScreen' }
    $form.Controls.AddRange(@(
      [System.Windows.Forms.Label] @{ Name = 'lbl'; Left = 10; Width = 250 }
      [System.Windows.Forms.ProgressBar] @{ Name = 'pb'; Minimum = 0; Maximum = 100; Top = 30; Left = 10; Width = 250 }
    ))
    $form.Show()
  }
  # Calculate the progress... 
  $timeLeft = $endTime - (Get-Date)
  if ($timeLeft -lt 0) { $timeLeft = [timespan] 0 }
  $completed = $timeLeft -eq 0
  $percent = (1 - $timeLeft.TotalSeconds / ($totalMinutes * 60)) * 100
  # ... and update the status label and progress bar
  # Write-Progress -Activity $activity -Status "$([math]::Floor($percent))% complete, $([math]::Ceiling($timeLeft.TotalSeconds)) seconds remaining..." -PercentComplete $percent
  $form.Controls['lbl'].Text = "$([math]::Floor($percent))% complete, $([math]::Ceiling($timeLeft.TotalSeconds)) seconds remaining..."
  $form.Controls['pb'].Value = $percent 
  # NOTE: This is crucial to make the form paint and to to keep it responsive.
  #       If the timer interval is too long, the form will be sluggish to respond to attempts to move or close it.
  [System.Windows.Forms.Application]::DoEvents()
  # If the time has elapsed or the form has been closed, close the form (if it isn't already closed),
  # and signal that fact to the calling thread.
  if ($completed -or -not $form.Visible) { $Event.MessageData.AbortedAt = if (-not $form.Visible) { $percent }; $form.Dispose(); $Event.MessageData.Done = $true }
} -MessageData $dto

# Start the timer, which displays the form with the progress bar.
$timer.Start()

try { 
    "Test output"
    # Wait until the timer has elapsed or the form has been closed.
    while (-not $dto.Done) {
        Start-Sleep -Seconds 0.5
    }
    if ($dto.AbortedAt) {
      Write-Warning "Progress-bar window as manually closed at $($dto.AbortedAt.ToString('N2'))% complete."
    } else {
      "Progress-bar window auto-closed on completion."
    }

} finally {
   # Clean up.
   $timer.Stop()
   Remove-Job $eventJob -Force
}