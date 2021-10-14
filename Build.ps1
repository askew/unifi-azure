Start-Process 'bicep' -ArgumentList @('build', 'unifi.bicep', '--outfile', 'azuredeploy.json') -WorkingDirectory $PSScriptRoot -NoNewWindow -Wait

$armTemplate = Join-Path $PSScriptRoot 'azuredeploy.json'
$cloudInitFile = Join-Path $PSScriptRoot '.\cloud-config.yml'
$setupScript = Join-Path $PSScriptRoot '.\unifi-setup.sh'

# Make sure the install script has LF end-of-lines and is UTF8 encoded.
$Data = [Text.Encoding]::UTF8.GetBytes( (Get-Content $setupScript | Join-String -Separator "`n") )

# Now GZip and Base-64 encode the text.
$output = [System.IO.MemoryStream]::new()
$gzipStream = New-Object System.IO.Compression.GzipStream $output, ([IO.Compression.CompressionMode]::Compress)
$gzipStream.Write($Data, 0, $Data.Length)
$gzipStream.Close()
$base64Script = [Convert]::ToBase64String($output.ToArray())

# Replace the "SETUPSCRIPT" placeholder in the cloud-init with the encoded script
$init = Get-Content $cloudInitFile `
| ForEach-Object { $_ -replace 'SETUPSCRIPT', "$base64Script" } `
| Join-String -Separator "`n"

# Load the JSON arm template
$arm = Get-Content $armTemplate -Raw | ConvertFrom-Json

# Replace the 'cloudInitFormat' variable value.
$cloudInitVar = get-member -InputObject ($arm.variables) -Type NoteProperty -Name 'cloudInitFormat'
if ($null -ne $cloudInitVar) {
    $arm.variables.cloudInitFormat = $init
}
else {
    Write-Error "Cannot find variable cloudInitFormat."
    Exit 1
}

# And finally write the arm template back out.
$arm | ConvertTo-Json -Depth 100 -EscapeHandling Default | Set-Content $armTemplate -Encoding UTF8

Write-Host "Written ARM template $armTemplate"
