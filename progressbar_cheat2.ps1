Add-Type -AssemblyName System.Windows.Forms

$objForm = New-Object System.Windows.Forms.Form
$objForm.Text = "Test"
$objForm.Size = New-Object System.Drawing.Size(400,200)
$objForm.FormBorderStyle = 'Fixed3D'
$objForm.MaximizeBox = $false
$objForm.MinimizeBox = $false
$objForm.StartPosition = "CenterScreen"

$amount = 1500

$ProgressBar = New-Object System.Windows.Forms.ProgressBar
$ProgressBar.Minimum = 0
$ProgressBar.Maximum = $amount
$ProgressBar.Location = new-object System.Drawing.Size(10,80)
$ProgressBar.size = new-object System.Drawing.Size(300,20)
$objForm.Controls.Add($ProgressBar)
$i=1

#Display progress
while($i -le $amount){
$ProgressBar.Value = $i
$i++
}
for($i = 1; $i -le $amount;$i++){}
$objForm.ShowDialog() | Out-Null
$objForm.Dispose()