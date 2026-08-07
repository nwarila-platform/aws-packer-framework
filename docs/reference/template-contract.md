# Template Variable Contract

This document defines the guaranteed variable set that the framework passes to every consumer
user-data template via `templatefile()`. Consumer templates can use any of these variables.
Changing this contract is a **breaking change** that must follow semantic versioning.

## Credentials

| Variable | Type | Source | Description |
|---|---|---|---|
| `deploy_user_name` | string | `var.deploy_user_name` | Communicator username (the source AMI's cloud-init default user for Linux) |

SSH key material is a Packer-generated temporary EC2 keypair injected through EC2 keypair
plumbing, and Linux privilege escalation uses the AMI's passwordless sudo grant — so no
password, hash, or key variables flow through the template contract.

## Locale

| Variable | Type | Default | Description |
|---|---|---|---|
| `os_language` | string | `"en_US"` | OS language/locale |
| `os_keyboard` | string | `"us"` | Keyboard layout |
| `os_timezone` | string | `"UTC"` | System timezone |

## OS Metadata

| Variable | Type | Source | Description |
|---|---|---|---|
| `os_family` | string | `var.packer_image.os_family` | `"linux"` or `"windows"` |
| `os_name` | string | `var.packer_image.os_name` | e.g. `"rhel"`, `"ubuntu"`, `"windows-server"` |
| `os_version` | string | `var.packer_image.os_version` | e.g. `"8"`, `"24.04"`, `"2022"` |

## Build Context

| Variable | Type | Source | Description |
|---|---|---|---|
| `build_region` | string | normalized | AWS region the build instance runs in |
| `build_communicator` | string | normalized | `"ssh"` or `"winrm"` |

## Hardware Summary

| Variable | Type | Source | Description |
|---|---|---|---|
| `hw_instance_type` | string | normalized | Build instance type (e.g. `"t3.medium"`) |
| `hw_root_device_name` | string | first mapping | Root device name (e.g. `"/dev/sda1"`) |
| `hw_root_volume_size` | number | first mapping | Root volume size in GiB |

## Usage in Templates

cloud-init example:

```yaml
#cloud-config
timezone: ${os_timezone}
locale: ${os_language}
```

OS-specific values such as package lists, repo mirrors, and first-boot commands belong
directly in the consumer's user-data template (or its `extra_vars` map, which is merged into
the render context). The framework contract provides the shared variables above; everything
else is owned by the template file itself.
