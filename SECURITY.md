# Security Policy

## Supported Versions

This repository is currently in a pre-1.0 transition state while the framework boundary and
consumer-owned Ansible model settle. Until multiple tagged release lines exist, the supported
security surface is:

- the current `main` branch
- the latest tagged release, once release automation starts publishing real versions

No previous-minor support matrix is published yet because the repository does not currently
evidence multiple maintained release lines.

## Reporting a Vulnerability

**Please do NOT report security vulnerabilities through public GitHub issues.**

Instead, report them via email to **reports@nicholaswarila.com** with the
following information:

- Description of the vulnerability
- Steps to reproduce (or proof-of-concept)
- Affected versions
- Any potential mitigations you've identified

### What to expect

| Milestone | Target |
|-----------|--------|
| Acknowledgement | Within 48 hours |
| Initial assessment | Within 7 days |
| Fix or mitigation | Within 30 days (severity-dependent) |

You will receive updates at each milestone. If the vulnerability is accepted, you will
be credited in the release notes unless you prefer to remain anonymous.

## Coordinated Disclosure

We follow a coordinated disclosure model:

1. Reporter submits the vulnerability privately.
2. We acknowledge receipt and begin investigation.
3. We develop and test a fix.
4. We release the fix and publish an advisory.
5. Reporter is free to publish details after the fix is released.

We ask that you give us reasonable time to address the issue before any public
disclosure. We will work with you to agree on a timeline.

## Scope

The following are **in scope** for security reports:

- Packer configurations that produce insecure AMIs
- Weaknesses in the framework's hardened defaults (IMDSv2 enforcement, EBS encryption,
  owner-scoped source AMI resolution)
- Secrets or credentials exposed in build artifacts, user data, or logs
- CI/CD pipeline vulnerabilities (workflow injection, secret leakage, OIDC role misuse)
- User-data template configurations that bypass intended security controls

The following are **out of scope**:

- Vulnerabilities in upstream dependencies (Packer, Ansible, AWS services) — report these
  to the respective maintainers
- Issues requiring access to the AWS account outside the build role's permissions
- Denial of service against build infrastructure
- Consumer-owned Ansible role or playbook security issues

## Security Features

This project implements the following security controls:

- **No static credentials** — the variable contract has no access-key inputs; builds
  authenticate through the ambient AWS credential chain (GitHub OIDC role assumption in CI)
- **IMDSv2 enforced** by normalized metadata defaults (`http_tokens = required`)
- **EBS encryption by default** for build volumes and the registered AMI (`encrypt_boot`)
- **Owner-scoped source AMI resolution** — unscoped AMI filters are rejected at validate
  time to prevent resolving a look-alike AMI from an untrusted account
- **Secret scanning** via Gitleaks in the Security workflow (org `reusable-iac-security`) and at pre-commit
- **Dependency scanning** via Trivy (filesystem) and Renovate (GitHub Actions
  SHA pins, Packer, OPA, and tooling versions)
- **SHA-pinned GitHub Actions** to prevent supply chain attacks via mutable tags

### Security Notes for Shipped Examples

- **Temporary security group:** The RHEL 8 example sets
  `temporary_security_group_source_cidrs = ["0.0.0.0/0"]` as a bootstrap exception for
  default-VPC builds. Production environments should scope this to the CI egress CIDR or
  use `ssh_interface = "session_manager"` with no inbound rules at all.
- **User data:** Rendered user data is readable from the instance metadata service for the
  life of the build instance. The framework contract never routes secrets through it, and
  consumer templates must not either.
- **Partition layout:** Cloud AMI builds inherit the source AMI's single-root-volume
  layout. STIG controls requiring separate `/home`, `/tmp`, `/var`, `/var/log`, and
  `/var/log/audit` partitions need a custom-partitioned source AMI or documented exceptions.
