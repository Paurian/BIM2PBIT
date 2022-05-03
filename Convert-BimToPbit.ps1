# Conversion From BIM to PBIT

param( [String]$BimFilePath="", [String]$OutputDirectory=".\Output", [String]$NewModelName="", [Int32]$DefaultTimeout=30 )

Set-StrictMode -Version Latest
# Set-PSRepository -Name PSGallery -InstallationPolicy Trusted

$ErrorActionPreference = "Stop"

if ( ($PSBoundParameters.Count -eq 0) -or ($BimFilePath -eq "") ) {
    Write-Output ( "--------------------------------------------------------------------------------------------------------------------" );
    Write-Output ( "-- No Argument Was Specified.                                                                                     --" );
    Write-Output ( "--------------------------------------------------------------------------------------------------------------------" );
    Write-Output ( "-- Usage:                                                                                                         --" );
    Write-Output ( "-- Convert-BimToPbit -BimFilePath [string] -PbitFilePath [string]                                                 --" );
    Write-Output ( "--------------------------------------------------------------------------------------------------------------------" );
    Write-Output ( "-- BimFilePath is the path to the input BIM file. E.G. ""C:\Some Directory\MyModel.Bim"" or "".\MyModel.Bim""     --" );
    Write-Output ( "-- OutputDirectory is the path to the output PBIT file. E.G. ""C:\temp\PutItHere""                                --" );
    Write-Output ( "--                                                                                                                --" );
    Write-Output ( "-- If you do not specify an Output Directory, the folder ""Output"" in the execution path is used.                --" );
    Write-Output ( "--------------------------------------------------------------------------------------------------------------------" );
    Exit
}


$FullPbitSkeletonFilePath = [IO.Path]::GetFullPath( "$(Get-Location)\SkeletonDataModelSchema.json" ) 
if ( (Test-Path -Path $FullPbitSkeletonFilePath) -eq $False ) {
    Write-Output ( "The SkeletonDataModelSchema.json file is missing from the expected path:" );
    Write-Output ( "  $($FullPbitSkeletonFilePath)" );
    Exit
}

$PbitTemplateFolder = "pbit content"
$FullPbitTemplateFolderPath = [IO.Path]::GetFullPath( "$(Get-Location)\$($PbitTemplateFolder)" ) 
if ( (Test-Path -Path $PbitTemplateFolder) -eq $False ) {
    Write-Output ( "The '$($PbitTemplateFolder)' directory is missing from the expected path:" );
    Write-Output ( "  $($FullPbitTemplateFolderPath)" );
    Exit
}

if ( ($BimFilePath.Contains("\") = $True) -and ($BimFilePath.StartsWith(".") -eq $False) ) {
  $FullBimFilePath = [IO.Path]::GetFullPath( $BimFilePath )
} else {
  $FullBimFilePath = [IO.Path]::GetFullPath( "$(Get-Location)\$($BimFilePath)" ) 
}
if ( (Test-Path -Path $FullBimFilePath) -eq $False ) {
    if ( ($FullBimFilePath.Contains("\") = $True) -and ($FullBimFilePath.StartsWith(".") -eq $False) ) {
      Write-Output ( "The BIM file couldn't be found at the path you provided:" );
      Write-Output ( "  $($FullBimFilePath)" );
    } else {
      Write-Output ( "The BIM file $($FullBimFilePath) couldn't be found from the relative path:" );
      Write-Output ( "  $($FullBimFilePath)" );
    }
    Exit
}

$ModelName = $NewModelName
if ($NewModelName -eq "") {
  $ModelName = (Get-ChildItem $FullBimFilePath).BaseName
}

if ( $OutputDirectory.StartsWith(".") ) {
  $FullOutputDirectoryPath = [IO.Path]::GetFullPath( "$(Get-Location)\$($OutputDirectory)" ) 
} else {
  $FullOutputDirectoryPath = [IO.Path]::GetFullPath( $OutputDirectory )
}
$FullWorkFolderPath = [IO.Path]::GetFullPath( "$($FullOutputDirectoryPath)\$($ModelName)_pbit" ) 
$FullDataModelSchemaPath = [IO.Path]::GetFullPath( "$($FullWorkFolderPath)\DataModelSchema" )
$FullDataModelSchemaJsonDbgPath = [IO.Path]::GetFullPath( "$($FullDataModelSchemaPath).json" )
$FullBimSchemaJsonDbgPath = [IO.Path]::GetFullPath( "$($FullDataModelSchemaPath).mod.json" )
$FullOutputZipPath = "$($FullOutputDirectoryPath)\$($ModelName).zip"
$PbitFileName = "$($ModelName).pbit"
$FullOutputPbitPath = "$($FullOutputDirectoryPath)\$($PbitFileName)"

# All directories/file-paths have been set up at this point.
try {
  $Bim = Get-Content $BimFilePath | ConvertFrom-JSON
} catch {
  Exit
}
$BimDataSources = $Bim.Model.DataSources
if ( $DefaultTimeout -gt 120 ) {
    Write-Output ( "Power BI Service has a cap on timeouts at 2 hours. The maximum of 2 hours will be used." );
    $DefaultTimeout = 120
}
$TimeoutHours = [Math]::Floor($DefaultTimeout / 60)
$TimeoutMinutes = $DefaultTimeout - (60 * $TimeoutHours)

$Pbit = Get-Content $FullPbitSkeletonFilePath | ConvertFrom-JSON

$ReplacementGuid = [guid]::NewGuid().ToString()
$Pbit.Name = $ReplacementGuid

$Pbit.Model.Tables += @($Bim.Model.Tables | ConvertTo-JSON -Depth 100 | ConvertFrom-JSON) # PowerShell Deep-Clone

$PartitionTemplateText = '[{"name":"Table~Name~GUID","mode":"import","source":{"type":"m","expression": '+
                     '"let\n    Source = Sql.Database(\"SERVER~NAME\", \"DB~NAME\", '+
                     '[Query=\"SQL~QUERY\", CommandTimeout=#duration(0, ' + $TimeoutHours + ', ' + $TimeoutMinutes +
                     ', 0)])\nin\n    Source"}}]'
$CalculatedPartitionText = '[{"name":"Table~Name~GUID","source":{"type":"calculated","expression":"DAX~EXPRESSION"}}]'
$ASQueryPartitionText = '[{"name":"Table~Name~GUID","mode":"import","source":{"type":"m","expression": ' +
                     '"AnalysisServices.Database(\"SERVER~NAME\", \"DB~NAME\", [Query=\"SQL~QUERY\", Implementation=\"2.0\"])"}}]'
$SimplePartitionText = '[{"name":"Table~Name~GUID","source":{"type":"m","expression":"SQL~QUERY"}}]'
$EmptyPartitionText = '[{"name":"Table~Name~GUID","source":{"type":"calculated","expression":let\nSource = Table.FromRows('+
                     'Json.Document(Binary.Decompress(Binary.FromText("i44FAA==", BinaryEncoding.Base64), Compression.Deflate)),'+
                     ' let _t = ((type nullable text) meta [Serialized.Text = true]) in type table [Column1 = _t]),\nin\n    Source}}]'

$RowNumberColumnTemplate = ('{"type": "rowNumber","name": "RowNumber-2662979B-1795-4F74-8F37-6A1BA8059B61",' +
                             '"dataType": "int64","isHidden": true,"isUnique": true,"isKey": true,' +
                             '"isNullable": false,"attributeHierarchy": {}}' | ConvertFrom-JSON)

# Tables might need to have the rowcount hidden field for Power BI Desktop to accept the schema
ForEach ($Table in $Pbit.Model.Tables) {
  $TableName = $Table.Name
  $DaxExpression = ""
  $PowerQuery = ""
  $PowerQueryLines = 0

  if ( "DataSource" -in $Table.Partitions[0].Source.PSobject.Properties.Name ) {
    $DataSourceName = $Table.Partitions[0].Source.DataSource
    $CS = ($BimDataSources | where name -eq $DataSourceName).ConnectionString
    $ServerName = [regex]::Match($CS, 'Data ?Source=([^;|\s]+)').Groups[1].Value
    $DBName = [regex]::Match($CS, 'Initial ?Catalog=([^;|\s]+)').Groups[1].Value
    $PartitionTemplate = ($PartitionTemplateText | ConvertFrom-JSON)
  } else {
    $DataSourceName = "NULL"
    $ServerName = "unknown"
    $DBName = "unknown"
    if ($Table.Partitions[0].Source.Type -eq "Calculated") {
      $PartitionTemplate = ($CalculatedPartitionText | ConvertFrom-JSON)
      $DaxExpression = (($Table.Partitions[0].Source.Expression -Join "`n") + "")
    } else {
      if ($null -ne $Table.Partitions[0].Source.Expression) {
        # We have a special expression situation
        $DataSourceName = [regex]::Match(($Table.partitions[0].source.expression -join " "), 'Source=([^;|\s]+)').Groups[1].Value
        if ($null -eq $DataSourceName -or $DataSourceName -eq "") {
          # Try Try Again
          $PowerQuery = $Table.partitions[0].source.expression -join " "
          $PowerQueryLines = $Table.partitions[0].source.expression.count
          $DataSourceName = [regex]::Match($PowerQuery, 'Source = \#"([^"]+)"').Groups[1].Value
          $PartitionTemplate = ($SimplePartitionText | ConvertFrom-JSON)
        }

        Write-Host "`n`n"
        for ($x = 1; $x -lt 10; $x++) {
          Write-Host "----------" -ForegroundColor Red -NoNewline
          Write-Host "----------" -ForegroundColor Yellow -NoNewline
        }
        Write-Host ""
        Write-Host "----------    Warning: This DataSource Is Not Conventionally Defined and Often Results In An Unusable PBIT Model" -ForegroundColor Yellow
        Write-Host "----------    >> $($DataSourceName) <<" -ForegroundColor Red
        for ($x = 1; $x -lt 10; $x++) {
          Write-Host "----------" -ForegroundColor Red -NoNewline
          Write-Host "----------" -ForegroundColor Yellow -NoNewline
        }
        Write-Host "`n`n"

        $BDS = ($BimDataSources | where name -eq $DataSourceName)
        if (("ConnectionDetails" -in $BDS.PSObject.Properties.Name) -and ($null -ne $BDS.ConnectionDetails)) {
          $CD = $BDS.ConnectionDetails
          $ServerName = $CD.Address.Server
          $DBName = $CD.Address.Database
          if ($null -ne $CD.Query) {
            $PowerQuery = $CD.Query.Replace("\n", "#(lf)").Replace("""","""""")
            $PowerQueryLines = ($CD.Query -Split "\n").Count
            $PartitionTemplate = ($ASQueryPartitionText | ConvertFrom-JSON)
          }
        } else {
          Write-Host ( $Table.Partitions[0].Source | ConvertTo-JSON ) -ForegroundColor Red
          $PartitionTemplate = ($EmptyPartitionText | ConvertFrom-JSON)
        }
      } else {
        Write-Host ( $Table.Partitions[0].Source | ConvertTo-JSON ) -ForegroundColor Red
        $PartitionTemplate = ($EmptyPartitionText | ConvertFrom-JSON)
      }
    }
  }

  if ( "Query" -in $Table.Partitions[0].Source.PSobject.Properties.Name ) {
    $SqlLines = @($Table.Partitions[0].Source.Query).Count
    $SqlQuery = (($Table.Partitions[0].Source.Query -Join "#(lf)") + "").Replace("""","""""")
  } else {
    if ( "Expression" -in $Table.Partitions[0].Source.PSobject.Properties.Name ) {
      $SqlLines = $PowerQueryLines
      $SqlQuery = $PowerQuery
    } else {
      $SqlLines = 0
      $SqlQuery = "SELECT * FROM unknown"
    }
  }

  Write-Host $Table.Name -ForegroundColor Green -NoNewline
  Write-Host " uses server: " -ForegroundColor White -NoNewline
  Write-Host $ServerName -ForegroundColor Yellow -NoNewline
  Write-Host " and DB: " -ForegroundColor White -NoNewline
  Write-Host $DBName -ForegroundColor Cyan -NoNewline
  Write-Host " from datasource: " -ForegroundColor White -NoNewline
  Write-Host $DataSourceName -ForegroundColor Red -NoNewline
  Write-Host " for a query that has " -ForegroundColor White -NoNewline
  Write-Host $SqlLines -ForegroundColor Magenta -NoNewline
  Write-Host " lines " -ForegroundColor White

  # Remove Annotations
  $Table.PSObject.Properties.Remove('Annotations')

  # Add RowNumber Column to the table
  $Table.Columns = @($RowNumberColumnTemplate) + $Table.Columns

  # Rebuild the Partitions
  $ReplacementGuid = [guid]::NewGuid().ToString()

  $Table.Partitions = @($PartitionTemplate)
  $Table.Partitions[0].Name = "$TableName-$ReplacementGuid"
  $Table.Partitions[0].Source.Expression = $Table.Partitions[0].Source.Expression.
    Replace("SERVER~NAME",$ServerName).Replace("DB~NAME",$DBName).
    Replace("SQL~QUERY",$SqlQuery).Replace("DAX~EXPRESSION",$DaxExpression)
}

if ($Bim.Model.PSObject.Properties.Match("Relationships").Count -gt 0) {
  $Pbit.Model.Relationships += @($Bim.Model.Relationships | ConvertTo-JSON -Depth 100 | ConvertFrom-JSON) # PowerShell Deep-Clone. Get all objects, don't append with [0]
}

$Pbit.Name = $ReplacementGuid

# Now we build our PBIT file:
Copy-Item -Path $FullPbitTemplateFolderPath -Destination $FullWorkFolderPath -Recurse -Force

$Utf16eNoBomEncoding = New-Object System.Text.UnicodeEncoding($False, $False)
[System.IO.File]::WriteAllLines($FullDataModelSchemaPath, ($Pbit | ConvertTo-JSON -Depth 100 -Compress -EscapeHandling EscapeNonAscii), $Utf16eNoBomEncoding)

# This is for debug purposes, only. Comment out when not debugging.

<#
# This is helps with debugging. Comment out for production
ForEach ($Table in $Bim.Model.Tables) {
  # Remove Annotations
  $Table.PSObject.Properties.Remove('Annotations')
  # Add RowNumber Column to the table
  $Table.Columns = @($RowNumberColumnTemplate) + $Table.Columns

  # Rebuild the Partitions
  # Just use the first partition and nix the rest.
  $Table.Partitions = @(@($Table.Partitions[0] | ConvertTo-JSON -Depth 100 | ConvertFrom-JSON)[0]) # PowerShell Deep-Clone
  $Table.Partitions[0].PSObject.Properties.Remove('Annotations')
}

$Utf8eNoBomEncoding = New-Object System.Text.UTF8Encoding($False, $False)
[System.IO.File]::WriteAllLines($FullDataModelSchemaJsonDbgPath, ($Pbit | ConvertTo-JSON -Depth 100 -EscapeHandling EscapeNonAscii), $Utf8eNoBomEncoding)
[System.IO.File]::WriteAllLines($FullBimSchemaJsonDbgPath, ($Bim | ConvertTo-JSON -Depth 100 -EscapeHandling EscapeNonAscii), $Utf8eNoBomEncoding)
Write-Output ( "Your json file is at: $($FullDataModelSchemaJsonDbgPath)" );
#>

# If we got here, we check and create the output directory. That way we don't create it if there's a stopping error earlier in the script

if ( (Test-Path -Path $FullOutputDirectoryPath) -eq $False ) {
  New-Item -ItemType "directory" -Path $FullOutputDirectoryPath
  Write-Output ( "Created path to output: $($FullOutputDirectoryPath)" );
} else {
  Write-Output ( "Verified path to output: $($FullOutputDirectoryPath)" );
}

# Everything that follows may be commented out during debug sessions, but should be active for production.
<##>
Compress-Archive -Path "$($FullWorkFolderPath)\*" -DestinationPath $FullOutputZipPath -Force

if ( (Test-Path -Path $FullOutputPbitPath) -eq $True ) {
  Remove-Item $FullOutputPbitPath
}

Rename-Item -Path $FullOutputZipPath -NewName $PbitFileName
Remove-Item $FullDataModelSchemaPath -Recurse -Force -Confirm:$false
Remove-Item $FullWorkFolderPath -Recurse -Force -Confirm:$false
Write-Output ( "Your new file is at: $($FullOutputPbitPath)" );

<##>