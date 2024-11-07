Param (
    [string]$Command,
    [int]$ProxyPort = 8888,
    [string]$Url = "http://cs260.meancat.com/delay"
)
$Command = $Command.ToLower()

# powershell version check --- print this out up front so we can figure out problems...
Write-Host "PowerShell Version:  $($PSVersionTable.PSVersion)" -ForegroundColor Green

$DetectedArch = if ($ENV:PROCESSOR_ARCHITECTURE -eq "AMD64") { "x64" } else { $ENV:PROCESSOR_ARCHITECTURE }

Write-Host "Architecture Detected: $DetectedArch" -ForegroundColor Green

# constants to some important files: 
$MSBuildExe = "C:\Program Files\Microsoft Visual Studio\2022\Community\MSBuild\Current\Bin\MSBuild.exe"
$ClientExe = Join-Path $PSScriptRoot "FakeHttpClient/$DetectedArch/Release/CS260_FakeHttpClient.exe"
$ResultsDir = Join-Path $PSScriptRoot "results/"

# create results dir if needed
New-Item -Path $ResultsDir -ItemType Directory -Force | Out-Null

function BuildClient {
    # requires the correct path to MSBuild (see above)
    VerifyMSBuildExists

    # Path to the C++ solution
    $solutionPath = Join-Path $PSScriptRoot "FakeHttpClient\FakeHttpClient.sln"

    # Build the solution
    Write-Host "Building FakeHttpClient ($DetectedArch)..." -ForegroundColor Blue
    & "$MSBuildExe" $solutionPath /p:Configuration=Release /p:Platform=$DetectedArch

    if ($LASTEXITCODE -ne 0) {
        Write-Error "Build failed!" -ForegroundColor Red
        exit $LASTEXITCODE
    } else {
        Write-Host "Build succeeded!" -ForegroundColor Green
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
        Write-Error "Client Executable not found at: $ClientExe"
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
    #while ($stream.Peek() -ge 0) {
    while(-not $stream.EndOfStream) {
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

    # print in "real time" (no buffering)
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
        Write-Output "Begin Test $testName $url $(Get-Date)"
        # Ensure logs are created
        $testLog = Join-Path $resultsDir "$TestName.txt"
        $errorLog = Join-Path $resultsDir "$TestName-error.txt"
        New-Item -Path $testLog -ItemType File -Force | Out-Null
        New-Item -Path $errorLog -ItemType File -Force | Out-Null

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
        Write-Host "End Test $TestName $(Get-Date)"
    } -ArgumentList $test.TestName, $test.Url, $ProxyPort, $ResultsDir, $ClientExe
}

function IsUserPrivileged {
    if ($IsMacOs -eq $true) {
        return true;
    }
    return ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]"Administrator")
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
        ExecuteTest -TestName "run-one" -Url $Url
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
            @{ TestName = "Valid-Google-NoSlash"; Url = "http://www.google.com" },
            @{ TestName = "Valid-Google-Slash"; Url = "http://www.google.com/" }
        )
        foreach($test in $testCases) {
            Write-Output "Run $test.TestName"
            ExecuteTestJob -TestName $test.TestName -Url $test.Url
            Write-Output "Done"
        }
        Write-Host "Waiting for all jobs ..."
        Wait-Job -State Running
        Get-Job | ForEach-Object {
            Receive-Job -Job $_
            Remove-Job -Job $_
        }
        Write-Host "Complete!"
    }
    "create-cert" {
        New-SelfSignedCertificate -Type CodeSigningCert -Subject "CN=DigiPen-CS260-ScriptSigning" -CertStoreLocation Cert:\CurrentUser\My
    }
    "export-cert" {
        $cert = Get-ChildItem -Path Cert:\CurrentUser\My | Where-Object { $_.Subject -match "DigiPen-CS260-ScriptSigning" }
        Export-Certificate -Cert $cert -FilePath "DigiPen-CS260-ScriptSigning.cer"
    }
    "sign-script" {
        $cert = Get-ChildItem -Path Cert:\CurrentUser\My | Where-Object { $_.Subject -match "DigiPen-CS260-ScriptSigning" }
        Set-AuthenticodeSignature -FilePath ".\assign3.ps1" -Certificate $cert
        Write-Host "Signed"
    }
    "import-cert" {
        # you must be admin for this to work
        $isAdmin = IsUserPrivileged
        if (-not $isAdmin) {
            Write-Host "You must be running as administrator to do that!"
            return
        }
        Import-Certificate -FilePath ".\DigiPen-CS260-ScriptSigning.cer" -CertStoreLocation Cert:\LocalMachine\TrustedPublisher
        Write-Host "Import done"
    }
    "set-execution-policy" {
        $isAdmin = IsUserPrivileged
        if (-not $isAdmin) {
            Write-Host "You must be running as administrator to do that!"
            return
        }
        Set-ExecutionPolicy RemoteSigned -Scope CurrentUser
        Write-Host "Done!"
    }
}

# SIG # Begin signature block
# MIIFtgYJKoZIhvcNAQcCoIIFpzCCBaMCAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCDZIhH4Vv/GAWLu
# FykFgwQ+cNZn57gA0FJp9v/ZJXfAa6CCAyAwggMcMIICBKADAgECAhBs1zNr0OVC
# rUrmSV3omiDSMA0GCSqGSIb3DQEBCwUAMCYxJDAiBgNVBAMMG0RpZ2lQZW4tQ1My
# NjAtU2NyaXB0U2lnbmluZzAeFw0yNDExMDcwMzI2NDhaFw0yNTExMDcwMzQ2NDha
# MCYxJDAiBgNVBAMMG0RpZ2lQZW4tQ1MyNjAtU2NyaXB0U2lnbmluZzCCASIwDQYJ
# KoZIhvcNAQEBBQADggEPADCCAQoCggEBAKGymtIxcfW3BfaHNzR8tNqR3/42L53J
# LqxU/EoquytTnR4Fv7IBA1AaLQI6OTEWAGt2IkBlD66KcmJY1v2XeYA4MrZeiWEL
# 9oyg0y+uY5ANzPDsPfXKCgcUgNajo49XGmh134tdLfru/FrRcJvQPuRwX+Qpg8kQ
# u5DGaea6VQoR6kG++zQvP9lPYOXaXlu8GR12tFeKLyosA/deb0kVsJsrft/DLRUX
# 7lHmzxT+g488dD5CA3E+m1jfzLBXryYhR9U9Etpbo0mB4sd6LIDAY11eqmLwz5T1
# mKMgk2rR+uR+7acVP7RBWyrMJMViU0LxqDE6kQ4a6Zx+5w4GsxiBN6kCAwEAAaNG
# MEQwDgYDVR0PAQH/BAQDAgeAMBMGA1UdJQQMMAoGCCsGAQUFBwMDMB0GA1UdDgQW
# BBQnMPcAIUqVQO7Sd12ivxBFlMAB7TANBgkqhkiG9w0BAQsFAAOCAQEAkcj92kpE
# Z5Aj1EXwp3aMj8ZcXHRmkITDYqvVNnCJV0LH8NMLV/gMiTdw09xxoUneHEwrqJnf
# tcQoptaxvQKNym5t0pZ9DAp99lEHahGNPU/LfDDNScCEWvATqvR2sALSOlBMhnPa
# nH5VCIXqfA57O6rEWF1VK6p4fFCP7+eqT3+HDs6JZLHWoS0nHCTBtkLm1c8XLM2S
# g4KPlEhCDXXcX+J2s1r8TWeMARU3do7RPGgeer3Al4URqPhkwqbU+87FeCfgNbsF
# Dq4JiGrZRK51XL2nizKLmjQr+e8jRTa9rF5kpKKqMDC80XDOJvrRpke7281Xc929
# DDo2IdTHf57eTjGCAewwggHoAgEBMDowJjEkMCIGA1UEAwwbRGlnaVBlbi1DUzI2
# MC1TY3JpcHRTaWduaW5nAhBs1zNr0OVCrUrmSV3omiDSMA0GCWCGSAFlAwQCAQUA
# oIGEMBgGCisGAQQBgjcCAQwxCjAIoAKAAKECgAAwGQYJKoZIhvcNAQkDMQwGCisG
# AQQBgjcCAQQwHAYKKwYBBAGCNwIBCzEOMAwGCisGAQQBgjcCARUwLwYJKoZIhvcN
# AQkEMSIEIJVZvq0mdU6oFH5iK/BW/JhtEyAyYO49+NmB3V4BDkjfMA0GCSqGSIb3
# DQEBAQUABIIBABI4kSgbYRaOp+HKEjZ4Wml8EiIMxhpJTAx9765TC8V1ot+Yzsg1
# rcWFerLLyq0vP5sagLsopN5Gj4c78SnF+MXlrusEizas/oxQGyZKJN38Puqr7udm
# m73zyWwTISyT9gp7dzKSJx46z1AOsR+vj+CACwIPLcmzUSVNyaXvlr87pND/cygo
# OTnDrouZ39f6ShaIaCVU8KyUt8s8FvyG98642ZsGF9Ui3a+hnvEertAzizZI6WG1
# GY1EO4gDLxyUdJPYKn0XeGfsrzNJIXofNpvIdi5mH0fEHjEOncc+XPFJg73tf8vz
# RElYe5R6dCuXsd0wpj8hCna5FjxAYqlps48=
# SIG # End signature block
