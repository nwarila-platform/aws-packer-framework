$ErrorActionPreference = "Stop"

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
$packerDir = Join-Path $repoRoot "packer"
$tmpDir = Join-Path ([System.IO.Path]::GetTempPath()) ([System.IO.Path]::GetRandomFileName())

New-Item -ItemType Directory -Path $tmpDir | Out-Null

try {
    $stubPlaybook = Join-Path $tmpDir "validation-playbook.yml"
    $stubPlaybookHcl = $stubPlaybook -replace "\\", "/"
    $stubAnsiblePlaybook = Join-Path $tmpDir "ansible-playbook.cmd"

    @"
---
- name: Validation-only Ansible stub
  hosts: all
  gather_facts: false
  tasks:
    - name: Emit validation marker
      ansible.builtin.debug:
        msg: validation-only stub
"@ | Set-Content -Path $stubPlaybook -NoNewline

    @"
@echo off
if "%~1"=="--version" (
  echo ansible-playbook [core 2.18.0]
  exit /b 0
)
exit /b 0
"@ | Set-Content -Path $stubAnsiblePlaybook -NoNewline

    $env:PATH = "$tmpDir;$env:PATH"

    function Invoke-NativeCommand {
        param(
            [Parameter(Mandatory = $true)]
            [string] $Executable,
            [Parameter()]
            [string[]] $Arguments = @()
        )

        & $Executable @Arguments
        if ($LASTEXITCODE -ne 0) {
            throw "Command failed: $Executable $($Arguments -join ' ')"
        }
    }

    function New-OverrideFile {
        param(
            [Parameter(Mandatory = $true)]
            [string] $OverridePath
        )

        @"
aws_region       = "us-east-1"
deploy_user_name = "ec2-user"

ansible_config = {
  playbook_path     = "$stubPlaybookHcl"
  requirements_path = null
  roles_path        = null
  config_path       = null
  extra_vars        = {}
}
"@ | Set-Content -Path $OverridePath -NoNewline
    }

    function Invoke-ExampleValidation {
        param(
            [Parameter(Mandatory = $true)]
            [string] $ExampleName,
            [Parameter(Mandatory = $true)]
            [string] $ExampleFile
        )

        $overrideFile = Join-Path $tmpDir "$ExampleName.pkrvars.hcl"
        New-OverrideFile -OverridePath $overrideFile

        Write-Host "Validating $ExampleName..."
        Invoke-NativeCommand -Executable "packer" -Arguments @(
            "validate",
            "-var-file=$ExampleFile",
            "-var-file=$overrideFile",
            "."
        )
    }

    function Assert-SourceAmiRequired {
        param(
            [Parameter(Mandatory = $true)]
            [string] $ExampleFile
        )

        $overrideFile = Join-Path $tmpDir "source-ami-required.pkrvars.hcl"
        $nullSourceAmiFile = Join-Path $tmpDir "source-ami-null.pkrvars.hcl"
        $expectedMessage = "The source_ami value must be supplied explicitly by the caller."
        New-OverrideFile -OverridePath $overrideFile

        @"
source_ami = null
"@ | Set-Content -Path $nullSourceAmiFile -NoNewline

        Write-Host "Validating source_ami required guard..."
        $output = & "packer" @(
            "validate",
            "-var-file=$ExampleFile",
            "-var-file=$overrideFile",
            "-var-file=$nullSourceAmiFile",
            "."
        ) 2>&1
        $exitCode = $LASTEXITCODE
        $outputText = $output | Out-String

        if ($exitCode -eq 0) {
            throw "packer validate succeeded with source_ami = null"
        }
        if ($outputText -notlike "*$expectedMessage*") {
            Write-Error $outputText
            throw "missing expected source_ami validation message"
        }

        # The packer call above is intentionally non-zero. Clear $LASTEXITCODE so the
        # script's overall exit code reflects assertion success rather than that failure.
        $global:LASTEXITCODE = 0
    }

    Push-Location $packerDir
    Invoke-NativeCommand -Executable "packer" -Arguments @("init", ".")
    Invoke-ExampleValidation `
        -ExampleName "rhel-8" `
        -ExampleFile (Join-Path $repoRoot "examples\packer\rhel-8\rhel-8.pkrvars.hcl")
    Assert-SourceAmiRequired `
        -ExampleFile (Join-Path $repoRoot "examples\packer\rhel-8\rhel-8.pkrvars.hcl")
}
finally {
    Pop-Location -ErrorAction SilentlyContinue
    Remove-Item -Path $tmpDir -Recurse -Force -ErrorAction SilentlyContinue
}
