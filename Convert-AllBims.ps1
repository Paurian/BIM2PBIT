# PowerShell -Recurse parameter
if ($PSVersionTable.PSVersion.Major -ge 7) {
  $Directory = "C:\GitProjects\EA-Main-Repository\Analysis Services\"
  $SplitAt = 4
} else {
  $Directory = "\\?\C:\GitProjects\EA-Main-Repository\Analysis Services\"
  $SplitAt = 7
}

$BimTable = (Get-ChildItem -Path $Directory -Include *.bim -Depth 4 | Sort-Object Name)

foreach ($bt in $BimTable) {
  $dir = $bt.DirectoryName
  $cpath = $dir.Split("\")[$SplitAt]
  $dir = "C:\GitProjects\EA-Main-Repository\Models"
  $file = $bt.FullName.Replace("\\?\", "")
  $nmn = $bt.BaseName

  if ($nmn -eq "Model") {
    $nmn = $cpath
  }

  $nmn = $nmn.Replace("Model", "")

  # Write-Host "Working On Model $($nmn) for $($file) : $($cpath -join ":")" -foregroundcolor yellow

  if (!( Test-Path -Path $dir )) {
    New-Item -ItemType directory -Path $dir
    Write-Host "New folder created"
  }
  else
  {
    # Write-Host "Folder already exists"
  }

  Write-Host "& .\Convert-BimToPbit.ps1 -BimFilePath ""$file"" -OutputDirectory ""$dir"" -NewModelName ""$($nmn)_Model"""
  & .\Convert-BimToPbit.ps1 -BimFilePath "$file" -OutputDirectory "$dir" -NewModelName "$($nmn)_Model"
  Write-Host ""
  Write-Host ""
}
