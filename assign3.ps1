Param (
    [string]$Command,
    [int]$ProxyPort = 8888,
    [string]$TestUrl = "http://cs260.meancat.com/delay"
)
$Command = $Command.ToLower()

# powershell version check --- print this out up front so we can figure out problems...
Write-Host "PowerShell Version:  $($PSVersionTable.PSVersion)" -ForegroundColor Green
Write-Host "Architecture Detected: $ENV:PROCESSOR_ARCHITECTURE" -ForegroundColor Green

# constants to some important files: 
$MSBuildExe = "C:\Program Files\Microsoft Visual Studio\2022\Community\MSBuild\Current\Bin\MSBuild.exe"
$ClientExe = Join-Path $PSScriptRoot "FakeHttpClient/Release/CS260_FakeHttpClient.exe"
$ResultsDir = Join-Path $PSScriptRoot "results/"

function BuildClient {
    # Determine architecture and set MSBuild architecture
    $arch = if ($ENV:PROCESSOR_ARCHITECTURE -eq "AMD64") { "x64" } else { "x86" }

    # requires the correct path to MSBuild (see above)
    VerifyMSBuildExists

    # Path to the C++ solution
    $solutionPath = Join-Path $PSScriptRoot "FakeHttpClient\FakeHttpClient.sln"

    # Build the solution
    Write-Host "Building FakeHttpClient ($arch)..." -ForegroundColor Blue
    & "$msbuildPath" $solutionPath /p:Configuration=Release /p:Platform=$arch

    if ($LASTEXITCODE -ne 0) {
        Write-Error "Build failed!" -ForegroundColor Red
        exit $LASTEXITCODE
    } else {
        Write-Host "Build succeeded!" -ForegroundColor Green
    }
}

function VerifyMSBuildExists {
    if (-not (Test-Path $MSBuildExe)) {
        Write-Error "msbuild.exe not found (tried $MSBuildExe)" -ForegroundColor Red
        exit 1
    }
}

function VerifyClientExists {
    if (-not (Test-Path $ClientExe)) {
        Write-Error "Client Executable not found at $ClientExe" -ForegroundColor Red
        return $false
    }
    return $true
}

function CreateClientProcess {
    param([string]$url)
    $procInfo = New-Object System.Diagnostics.ProcessStartInfo
    $procInfo.FileName = $ClientExe
    $procInfo.Arguments = "$url $ProxyPort"
    $procInfo.RedirectStandardOutput = $true
    $procInfo.RedirectStandardError = $true
    $procInfo.UseShellExecute = $false
    $procInfo.CreateNoWindow = $true

    $proc = New-Object System.Diagnostics.Process
    $proc.StartInfo = $procInfo
    return $proc
}

function PrintStreamToScreen {
    Param($stream, [bool]$isError)
    while ($null -ne $stream -and $stream.Peek() -ge 0) {
        $c = [char]$stream.Read()
        if ($isError) {
            Write-Host -NoNewLine $c -ForegroundColor Red
        } else {
            Write-Host -NoNewLine $c
        }
    } 
}

function ExecuteTest {
    Param([string]$TestName, [string]$Url)
    $proc = CreateClientProcess $Url
    if (-not $proc.Start()) {
        Write-Output "Error: $ClientExe failed to start"
        exit 1
    }

    $stdoutStream = $proc.StandardOutput
    $stderrStream = $proc.StandardError

    # print in "real time" (no or little buffering)
    while (-not $proc.HasExited) {
        PrintStreamToScreen -stream $stdoutStream -isError $false
        PrintStreamToScreen -stream $stderrStream -isError $true
    }
    PrintStreamToScreen -stream $stdoutStream -isError $false
    PrintStreamToScreen -stream $stderrStream -isError $true
    Write-Host "$TestName completed."
}

function ExecuteTestJob {
    Param([string]$TestName, [string]$Url)
    Start-Job -ScriptBlock  {
        Param($testName, $url, $port, $resultsDir, $clientExe)
        # Ensure logs are created
        $testLog = Join-Path $resultsDir "$TestName.txt"
        $errorLog = Join-Path $resultsDir "$TestName-error.txt"

        # Use Start-Process with output redirection
        $proxyArgs = "$url $port"
        $process = Start-Process -FilePath $clientExe `
                                      -ArgumentList $proxyArgs `
                                      -NoNewWindow `
                                      -RedirectStandardOutput $testLog `
                                      -RedirectStandardError $errorLog `
                                      -PassThru

        # Wait for the process to finish or timeout after 1 minute
        $timeout = 30
        $process | Wait-Process -Timeout $timeout
        Write-Host "Test $TestName ended"
    } -ArgumentList $test.TestName, $test.Url, $ProxyPort, $ResultsDir, $ClientExe
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
        # this assumes your assignment is already running and listening to $ProxyPort
        # start the fake http client and capture input and output
        if (-not (VerifyClientExists)) {
            BuildClient
        }

        # just run vs. one url
        ExecuteTest -TestName "run-one" -Url $TestUrl
        exit 0
    }
    "runAll" {
        Write-Output "Run all the tests!"
        $testCases = @(
            @{ TestName = "Valid-Delay-1-DNS"; Url = "http://cs260.meancat.com/delay" },
            @{ TestName = "Valid-Delay-2-DNS"; Url = "http://cs260.meancat.com/delay" }
            @{ TestName = "Valid-Delay-3-DNS"; Url = "http://cs260.meancat.com/delay" },
            @{ TestName = "Valid-Delay-4-DNS"; Url = "http://cs260.meancat.com/delay" },
            @{ TestName = "Valid-Delay-IP"; Url = "http://52.12.14.56/delay" }
            #@{ TestName = "Valid-Google-NoSlash"; Url = "http://www.google.com" },
            #@{ TestName = "Valid-Google-Slash"; Url = "http://www.google.com/" }
        )
        foreach($test in $testCases) {
            ExecuteTestJob -TestName $test.TestName -Url $test.Url
        }
        Write-Host "Waiting for all jobs ..."
        Wait-Job -State Running
        Get-Job | ForEach-Object {
            Receive-Job -Job $_
            Remove-Job -Job $_
        }
        Write-Host "Complete!"
    }
}