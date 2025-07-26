# Сначала узнай смещение раздела
powershell "Get-Partition -DiskNumber 3 -PartitionNumber 2 | Select Offset"

# Затем используй dd с параметром skip
F:\workfolder\copy_core\dd.exe if="\\.\PhysicalDrive3" of="F:\workfolder\usb_image.img" bs=512 skip=<OFFSET_IN_SECTORS> --progress
pause