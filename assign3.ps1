Param (
    [string]$Command,
    [int]$Port = 8888,
    [string]$TestUrl = "http://cs260.meancat.com/delay"
)
$Command = $Command.ToLower()

# powershell version check --- print this out up front so we can figure out problems...
Write-Host "PowerShell Version:  $($PSVersionTable.PSVersion)"
Write-Host "Architecture Detected: $ENV:PROCESSOR_ARCHITECTURE"

# constants to some important files: 
$MSBuildExe = "C:\Program Files\Microsoft Visual Studio\2022\Community\MSBuild\Current\Bin\MSBuild.exe"
$ClientExe = Join-Path $PSScriptRoot "FakeHttpClient/Release/CS260_FakeHttpClient.exe"
$ResultsDir = Join-Path $PSScriptRoot "results/"
Write-Host $ResultsDir


function BuildClient {
    # Determine architecture and set MSBuild architecture
    $arch = if ($ENV:PROCESSOR_ARCHITECTURE -eq "AMD64") { "x64" } else { "x86" }

    # requires the correct path to MSBuild (see above)
    VerifyMSBuildExists

    # Path to the C++ solution
    $solutionPath = Join-Path $PSScriptRoot "FakeHttpClient\FakeHttpClient.sln"

    # Build the solution
    Write-Host "Building FakeHttpClient ($arch)..."
    & "$msbuildPath" $solutionPath /p:Configuration=Release /p:Platform=$arch

    if ($LASTEXITCODE -ne 0) {
        Write-Error "Build failed!"
        exit $LASTEXITCODE
    } else {
        Write-Host "Build succeeded!"
    }
}

function VerifyMSBuildExists {
    if (-not (Test-Path $MSBuildExe)) {
        Write-Error "msbuild.exe not found (tried $MSBuildExe)"
        exit 1
    }
}

function VerifyClientExists {
    if (-not (Test-Path $ClientExe)) {
        Write-Error "Client Executable not found at $ClientExe"
        return $false
    }
    return $true
}

function CreateClientProcess {
    param([string]$url, [bool]$createNoWindow)
    $procInfo = New-Object System.Diagnostics.ProcessStartInfo
    $procInfo.FileName = $ClientExe
    $procInfo.Arguments = "$url $Port"
    $procInfo.RedirectStandardOutput = $true
    $procInfo.RedirectStandardError = $true
    $procInfo.UseShellExecute = $false
    $procInfo.CreateNoWindow = $createNoWindow

    $proc = New-Object System.Diagnostics.Process
    $proc.StartInfo = $procInfo
    return $proc
}

function PrintStr {
    Param($stream, [bool]$isError, [string]$logFile)
    
    while ($null -ne $stream -and $stream.Peek() -ge 0) {
        $c = [char]$stream.Read()
        if ($null -ne $logFile) {
            Add-Content -Path $logFile -Value $c
        }
        if ($isError) {
            Write-Host -NoNewLine $c -ForegroundColor Red
        } else {
            Write-Host -NoNewLine $c
        }
    } 
}

function ExecuteTest {
    Param([string]$TestName, [string]$Url)
    Write-Output "Running test $TestName for $Assignment..."

    $testLog = Join-Path $ResultsDir "$TestName.txt"
    $errorLog = Join-Path $ResultsDir "$TestName-error.txt"

    New-Item -Path $testLog -ItemType File -Force
    New-Item -Path $errorLog -ItemType File -Force

    $proc = CreateClientProcess $Url $true
    if (-not $proc.Start())
    {
        Write-Output "Error: $ClientExe failed to start"
        exit 1
    }

    Start-Job -ScriptBlock {
        Param($proc, $testLog, $errorLog)
        $stdoutStream = $proc.StandardOutput
        $stderrStream = $proc.StandardError
        while (-not $proc.HasExited) {
            PrintStr $stdoutStream $false $testLog
            PrintStr $stderrStream $true $errorLog
            Start-Sleep -Milliseconds 10
        }
        PrintStr $stdoutStream $false $testLog
        PrintStr $stderrStream $true $errorLog
    } -ArgumentList $proc, $testLog, $errorLog
}

# Function to wait for all jobs to complete
function WaitForAllTests {
    Write-Host "Waiting for all tests to complete..."
    
    $jobs = Get-Job
    if ($jobs.Count -gt 0) {
        Wait-Job -Job $jobs
        
        # Optionally, check job results and remove completed jobs
        $jobs | ForEach-Object {
            Receive-Job -Job $_
            Remove-Job -Job $_
        }
    }
    
    Write-Host "All tests completed."
}



switch -Regex ($Command) {
    "buildClient" {
        BuildClient
        if (-not (VerifyClientExists)) {
            Write-Host "No output found; Build failed?" -ForegroundColor Red
            exit 1
        }
    }
    "runOne" {
        # this assumes your assignment is already running and listening to $Port
        # start the fake http client and capture input and output
        if (-not (VerifyClientExists)) {
            BuildClient
        }

        # just run vs. one url
        ExecuteTest -TestName "run-one" -Url $TestUrl
        exit 0
    }
    "runAll" {
        Write-Output "Run all tests"
      
        # Create results directory for the assignment
        if (-not (Test-Path $ResultsDir)) {
            New-Item -ItemType Directory -Path $ResultsDir
        }
 
        # Run the tests
#        ExecuteTest -TestName "Valid-Google-NoSlash" -Url "http://www.google.com"
#        ExecuteTest -TestName "Valid-Google-Slash" -Url "http://www.google.com/"
#        ExecuteTest -TestName "Valid-Delay1-DNS" -Url "http://cs260.meancat.com/delay"
#        ExecuteTest -TestName "Valid-Delay2-DNS" -Url "http://cs260.meancat.com/delay"
#        ExecuteTest -TestName "Valid-Delay3-DNS" -Url "http://cs260.meancat.com/delay"
        ExecuteTest -TestName "Valid-Delay4-DNS" -Url "http://cs260.meancat.com/delay"
        ExecuteTest -TestName "Valid-Delay-IP" -Url "http://52.12.14.56/delay"

        WaitForAllTests
        Write-Host "Run All Complete!"
        exit 0
    }
}

<#
Write-Output "CS 260 ASSIGNMENT 3 AUTOMATION: $Assignment"

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