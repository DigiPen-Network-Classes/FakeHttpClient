Param (
    [ValidateSet(
    "runOne"
    )]
    [string]$Command,
    [int]$Port = 8888,
    [string]$TestUrl = "http://cs260.meancat.com/delay"
)
# powershell version check --- print this out so we can figure out problems
Write-Host "PowerShell Version:  $($PSVersionTable.PSVersion)"

$ClientExe = Join-Path $PSScriptRoot "CS260_Assignment3_Client.exe"
if (-not (Test-Path $ClientExe)) {
    Write-Error "Client executable $ClientExe not found!"
    exit 1
}

# this assumes your assignment is already running and listening to $Port
# start the client and capture input and output
switch -Regex ($Command) {
    "runOne" {
        # just run vs. one url
        $procInfo = New-Object System.Diagnostics.ProcessStartInfo
        $procInfo.FileName = $ClientExe
        $procInfo.Arguments = "$TestUrl $Port"
        $procInfo.RedirectStandardOutput = $true
        $procInfo.RedirectStandardError = $true
        $procInfo.UseShellExecute = $false
        $procInfo.CreateNoWindow = $true

        $proc = New-Object System.Diagnostics.Process
        $proc.StartInfo = $procInfo

        if (-not $proc.Start())
        {
            Write-Output "Error: $ClientExe failed to start"
            exit 1
        }

        $stdoutStream = $proc.StandardOutput
        $stderrStream = $proc.StandardError

        # continuously read from stdout and stderr, character by character
        while(-not $proc.HasExited) {
            # read stdout
            while ($stdoutStream.Peek() -ge 0) {
                $c = [char]$stdoutStream.Read()
                Write-Host -NoNewLine $c
            } 
            # read stderr
            <#
            Write-Host "check stderr"
            if ($stderrStream.Peek() -ge 0) {
                Write-Host "reading stderr" -ForegroundColor blue
                $c = [char]$stderrStream.Read()
                Write-Host "done reading stderr" -ForegroundColor blue
                Write-Host -NoNewLine $c -ForegroundColor Red
            }
                #>
            Start-Sleep -Milliseconds 10
        }

        Write-Host "out of loop"

        # after exit, print anything else
        while($stdoutStream.Peek() -ge 0) {
            $c = [char]$stdoutStream.Read()
            Write-Host -NoNewline $c
        }
        while ($stderrStream.Peek() -ge 0) {
            $c = [char]$stderrStream.Read()
            Write-Host -NoNewLine $c -ForegroundColor Red
        }

        # use exit code of client:
        exit $proc.ExitCode
    }
}

<#
Write-Output "CS 260 ASSIGNMENT 3 AUTOMATION: $Assignment"

# Create results directory for the assignment
$resultsDir = ".\results\$Assignment"
if (-not (Test-Path $resultsDir)) {
    New-Item -ItemType Directory -Path $resultsDir
}

# Building Debug Configuration
Write-Output "Building Debug for $Assignment..."
$buildDebugLog = "$resultsDir\build-debug.log"
Start-Process -FilePath "msbuild" -ArgumentList ".\$Assignment\CS260_Assignment3.vcxproj", "/p:Configuration=Debug" -NoNewWindow -Wait -RedirectStandardOutput $buildDebugLog

if ($LASTEXITCODE -ne 0) {
    Write-Output "DEBUG BUILD FAILURE - UNABLE TO TEST!"
    exit $LASTEXITCODE
}

# Building Release Configuration
Write-Output "Building Release for $Assignment..."
$buildReleaseLog = "$resultsDir\build-release.log"
Start-Process -FilePath "msbuild" -ArgumentList ".\$Assignment\CS260_Assignment3.vcxproj", "/p:Configuration=Release" -NoNewWindow -Wait -RedirectStandardOutput $buildReleaseLog

if ($LASTEXITCODE -ne 0) {
    Write-Output "RELEASE BUILD FAILURE - UNABLE TO TEST!"
    exit $LASTEXITCODE
}

# Start the release proxy process
Write-Output "Starting Release Proxy for $Assignment..."
Start-Process -FilePath ".\$Assignment\Release\CS260_Assignment3.exe" -ArgumentList "8888" -WindowStyle Hidden

# Define a function to run tests and capture results
function ExecuteTest {
    param (
        [string]$Assignment,
        [string]$TestName,
        [string]$Url
    )

    Write-Output "Running test $TestName for $Assignment..."
    $testLog = ".\results\$Assignment\$TestName.txt"
    $errorLog = ".\results\$Assignment\$TestName-error.txt"
    Start-Process -FilePath "cmd.exe" -ArgumentList "/c .\CS260_Assignment3_Client.exe $Url 8888 > $testLog 2> $errorLog" -NoNewWindow -Wait
}

# Run the tests
ExecuteTest $Assignment "Valid-Google-NoSlash" "http://www.google.com"
ExecuteTest $Assignment "Valid-Google-Slash" "http://www.google.com/"
ExecuteTest $Assignment "Valid-Delay1-DNS" "http://cs260.meancat.com/delay"
ExecuteTest $Assignment "Valid-Delay2-DNS" "http://cs260.meancat.com/delay"
ExecuteTest $Assignment "Valid-Delay3-DNS" "http://cs260.meancat.com/delay"
ExecuteTest $Assignment "Valid-Delay4-DNS" "http://cs260.meancat.com/delay"
ExecuteTest $Assignment "Valid-Delay-IP" "http://52.12.14.56/delay"

Write-Output "Testing for $Assignment - complete!"

exit $LASTEXITCODE

#>