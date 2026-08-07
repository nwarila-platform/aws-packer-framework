# AWS Packer Framework

[![CI](https://github.com/nwarila-platform/aws-packer-framework/actions/workflows/main-validation.yml/badge.svg)](https://github.com/nwarila-platform/aws-packer-framework/actions/workflows/main-validation.yml)
[![Security](https://github.com/nwarila-platform/aws-packer-framework/actions/workflows/security.yaml/badge.svg)](https://github.com/nwarila-platform/aws-packer-framework/actions/workflows/security.yaml)
[![Release](https://img.shields.io/github/v/release/nwarila-platform/aws-packer-framework)](https://github.com/nwarila-platform/aws-packer-framework/releases)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

A data-driven [Packer](https://www.packer.io/) framework for building hardened Amazon Machine Images. The framework owns the `amazon-ebs` builder contract, normalization layer, and CI validation flow. Consumer repositories bring their own source AMI pins, Ansible content, and environment-specific values.

## Purpose

This repository is an organizational framework, not a turnkey image factory. Its job is to give downstream repositories a stable, reusable AWS/Packer contract so teams inherit:

- secure infrastructure defaults (IMDSv2 enforced, EBS encryption on, owner-scoped source AMI resolution, no static credentials)
- a shared input schema
- consistent validation and CI behavior
- a clean separation between framework logic and consumer content

The framework does not decide which packages, hardening profile, or application stack an image should contain. Those decisions stay with the consumer repository.

## Ownership Model

| Layer | Owner | Default Source |
|-------|-------|----------------|
| Packer orchestration and variable contract | This framework | This repository |
| Source AMI pins and their audit trail | Consumer repo | Committed pkrvars files |
| User-data templates (cloud-init, EC2Launch) | Consumer repo | Shipped example in `examples/packer/` |
| Ansible roles, playbooks, Galaxy requirements | Consumer repo | [ansible-framework](https://github.com/nwarila-platform/ansible-framework) |

This repository ships example inputs only. It does not ship Ansible roles, playbooks, inventories, or `ansible.cfg`; consumers import those from [ansible-framework](https://github.com/nwarila-platform/ansible-framework) or an equivalent repository.

Base-image selection is owned externally. Consumers must supply `source_ami` — a pinned `ami_id` or an owner-scoped filter — in a committed pkrvars file whose diff history is the audit trail of which base image each build consumed. See [docs/explanation/architecture.md](docs/explanation/architecture.md#source-ami-boundary).

## Architecture

At a high level:

1. Consumer `.pkrvars.hcl` files provide environment-specific inputs.
2. `packer/locals.pkr.hcl` normalizes those inputs and renders the optional user-data template.
3. `packer/source.pkr.hcl` maps the normalized values into the `amazon-ebs` builder.
4. `packer/builds.pkr.hcl` runs the consumer-provided Ansible playbook, then writes the build manifest.

See [docs/explanation/architecture.md](docs/explanation/architecture.md) for design decisions and [docs/reference/template-contract.md](docs/reference/template-contract.md) for the template variable contract.

## Supported Operating Systems

| OS | Version | Base Image | Example | Status |
|----|---------|------------|---------|--------|
| RHEL | 8.x | Official Red Hat AMI (owner `309956199498`) | [examples/packer/rhel-8/](examples/packer/rhel-8/) | Validated example |

The generic `source_ami` + `user_data_template` contract supports any guest OS with a published AMI and an SSH- or WinRM-reachable first boot.

The shipped example is validated in CI, but consumers are still expected to:

- pin `source_ami` values appropriate for their account and region
- point `ansible_config.*` paths at consumer-owned Ansible content
- decide whether the example's open temporary-security-group CIDR is an acceptable bootstrap exception for their environment

## Prerequisites

| Tool | Version | Purpose |
|------|---------|---------|
| [Packer](https://www.packer.io/) | 1.15.0 | Image builder |
| [Ansible](https://docs.ansible.com/) | Consumer-defined | Consumer-owned provisioning content |
| AWS account | — | Build target (EC2, EBS, AMI permissions) |
| [pre-commit](https://pre-commit.com/) | 4.0+ | Local hook runner |

## AWS Build Role

Builds authenticate through the ambient AWS credential chain — GitHub OIDC role assumption in CI, SSO or instance profiles locally. The variable contract deliberately has no access-key inputs. Grant the build role the minimum EC2/EBS/AMI permissions Packer needs; the [amazon plugin's IAM task-or-instance-role policy](https://developer.hashicorp.com/packer/integrations/hashicorp/amazon#iam-task-or-instance-role) is the reference baseline. Scope `iam:PassRole` to the build instance profile only if you attach one.

## Quick Start

### 1. Clone and initialize

```bash
git clone https://github.com/nwarila-platform/aws-packer-framework.git
cd aws-packer-framework

cd packer
packer init .
```

### 2. Copy example inputs

```bash
# Packer example inputs
cp ../examples/packer/.env.example ./../.env.packer.example
cp ../examples/packer/rhel-8/rhel-8.pkrvars.hcl ./my-rhel8.pkrvars.hcl
```

The `.env.example` files are templates for values you should export into your shell or CI environment. They are not auto-loaded by Packer.

### 3. Configure your environment

- export `PKR_VAR_*` values for the region and deploy user from the copied Packer env example, and authenticate the AWS credential chain (SSO, OIDC, or a profile)
- edit `my-rhel8.pkrvars.hcl` for region, VPC placement, instance type, and AMI distribution settings
- point `ansible_config.*` paths at consumer-owned content

The framework requires `source_ami` to be supplied by the caller — there are no bundled base-image defaults, and unscoped AMI filters are rejected. The example pkrvars file pins the official Red Hat owner account and an owner-scoped RHEL 8.10 name filter.

The framework also accepts `PKR_VAR_aws_region` as a top-level CI-friendly override for the matching nested `packer_image.region` field.

### 4. Validate and build

```bash
# Packer validation and build
cd ../packer
packer validate \
  -var-file="my-rhel8.pkrvars.hcl" \
  .

packer build \
  -var-file="my-rhel8.pkrvars.hcl" \
  .
```

AMI names are suffixed with a build timestamp by the framework, so repeated builds never collide.

### 5. Install pre-commit hooks

```bash
pre-commit install
pre-commit install --hook-type commit-msg
```

## Project Structure

```text
aws-packer-framework/
|-- .config/
|-- .github/
|   |-- scripts/
|   |   |-- get_packer_version.sh
|   |   |-- validate_examples.sh
|   |   `-- validate_examples.ps1
|   `-- workflows/
|-- .vscode/
|-- docs/
|   |-- explanation/
|   |   `-- architecture.md
|   `-- reference/
|       `-- template-contract.md
|-- examples/
|   `-- packer/
|       |-- .env.example
|       `-- rhel-8/
|-- packer/
|   |-- builds.pkr.hcl
|   |-- data.pkr.hcl
|   |-- locals.pkr.hcl
|   |-- packer.pkr.hcl
|   |-- source.pkr.hcl
|   `-- variables.pkr.hcl
|-- .editorconfig
|-- .gitattributes
|-- .pre-commit-config.yaml
|-- .release-please-manifest.json
|-- release-please-config.json
|-- CHANGELOG.md
|-- CODE_OF_CONDUCT.md
|-- CONTRIBUTING.md
|-- LICENSE
|-- SECURITY.md
`-- SUPPORT.md
```

## CI/CD Pipeline

| Workflow | Trigger | What it does |
|----------|---------|--------------|
| Main Validation | Push to `main` touching `packer/**`, `examples/**`, `contract/**`, `tools/**`, `.github/scripts/**`, `.github/workflows/**`, `.pre-commit-config.yaml` (plus release-please outputs) | Reusable workflow contract check, Packer init/fmt/validate |
| PR Validation | Every PR to `main` (and merge queue) | Reusable workflow contract check, Packer init/fmt/validate |
| Security | Push/PR to `main`, merge queue, weekly schedule | Calls the org `reusable-iac-security` (Trivy IaC plus Gitleaks secret scan), `reusable-codeql`, and `reusable-scorecard` (OpenSSF Scorecard) reusables |
| Drift Gate | Every PR to `main` | Verifies this repo against the org baseline and the `packer-framework-template` baseline manifests |
| Repo Hygiene | PR to `main`, merge queue, weekly schedule | Calls the org `reusable-repo-hygiene` policy (SHA-pinned actions, exact pins, `pull_request_target` safety) |
| Release | Push to `main` (opt-in via `RELEASE_PLEASE_ON_PUSH`) or a published release | Runs release-please for changelog/releases and publishes release evidence/attestations |

Secret scanning and IaC scanning run once, in the Security workflow, through the org-owned
`reusable-iac-security` reusable; the validation workflows do not run Gitleaks inline. Two
additional workflows are callable rather than event-triggered: `reusable-packer-framework-build.yaml`
(the downstream build/validate entrypoint described below) and `reusable-release-evidence.yaml`
(invoked by the Release workflow).

## Downstream Integration

Downstream image repositories should call this framework through its reusable workflow when
they want CI to validate or build against a SHA-pinned framework revision. The workflow accepts the
same runner protocol input names as `NWarila/packer-framework-template`:

```yaml
jobs:
  validate-image-inputs:
    uses: nwarila-platform/aws-packer-framework/.github/workflows/reusable-packer-framework-build.yaml@0123456789abcdef0123456789abcdef01234567
    with:
      framework_ref: 0123456789abcdef0123456789abcdef01234567
      input_repo: nwarila-platform/<image-repo>
      input_ref: fedcba9876543210fedcba9876543210fedcba98
      overlay_paths: |
        packer/repos/public/=>packer/repos/public/
      var_file: |
        packer/repos/public/rhel-8.pkrvars.hcl
      build: false
      upload_artifacts: false
```

For privileged AMI builds, set `build: true` and pass AWS credentials as
reusable-workflow secrets. The workflow assumes the supplied IAM role via GitHub OIDC
(`aws-actions/configure-aws-credentials`), verifies the ambient identity, and then runs
`packer build`. No static access keys cross the workflow boundary.

```yaml
jobs:
  build-image:
    uses: nwarila-platform/aws-packer-framework/.github/workflows/reusable-packer-framework-build.yaml@0123456789abcdef0123456789abcdef01234567
    with:
      framework_ref: 0123456789abcdef0123456789abcdef01234567
      input_repo: nwarila-platform/<image-repo>
      input_ref: fedcba9876543210fedcba9876543210fedcba98
      overlay_paths: |
        packer/repos/public/=>packer/repos/public/
      var_file: |
        packer/repos/public/rhel-8.pkrvars.hcl
      build: true
      upload_artifacts: true
    secrets:
      aws_role_to_assume: ${{ secrets.AWS_PACKER_FRAMEWORK_ROLE_ARN }}
      aws_region: ${{ secrets.AWS_REGION }}
      deploy_user_name: ${{ secrets.DEPLOY_USER_NAME }}
```

This framework produces AMIs designed to be consumed by Terraform or OpenTofu. A downstream repo can check out its own consumer content next to this framework, place its `.auto.pkrvars.hcl` file in the framework `packer/` working directory, and run `packer validate .` / `packer build .` directly as long as it supplies:

- `source_ami` pinned in a committed pkrvars file
- `ansible_config` pointing at consumer-owned Ansible content, with `ansible-playbook` available on PATH in the runtime environment
- optional `user_data_template` pointing at a consumer-owned first-boot template

The build manifest under `packer/manifests/` records the AMI ID; downstream Terraform can also resolve the newest image by name prefix and tags:

```hcl
data "aws_ami" "rhel8" {
  most_recent = true
  owners      = ["self"]

  filter {
    name   = "name"
    values = ["rhel-8-*"]
  }

  filter {
    name   = "tag:ManagedBy"
    values = ["aws-packer-framework"]
  }
}
```

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines. This project uses [Conventional Commits](https://www.conventionalcommits.org/) and enforces them with pre-commit hooks.

## License

This project is licensed under the [MIT License](LICENSE).
