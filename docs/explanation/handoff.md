# Engineering Handoff

Date: 2026-08-07

## Current State

- Branch: `main` (initial scaffold, no remote history yet)
- Derived from: `nwarila-platform/proxmox-packer-framework` at its current `main`
  (conventions, repo hygiene, validation flow, runner protocol, and reusable
  workflow contract carried over; platform layers re-mapped to AWS per
  repo ADR-0001)
- Companion consumer repo: `nwarila-platform/secure-rhel8-ami` (RHEL 8 inventory,
  proof-of-consumption for this framework)

## What This Session Did

Scaffolded the AWS Packer framework from proxmox-packer-framework:

- `packer/` core rewritten for the `amazon-ebs` builder: `source_ami` replaces
  `boot_iso` (required, owner-scoped guard), `user_data_template` replaces
  `install_template`, `launch_block_device_mappings`/`vpc_config`/
  `metadata_options` replace the Proxmox hardware objects.
- Credential model changed: no Proxmox token variables, no
  secure-packer-bootstrapper. AWS credentials come from the ambient chain
  (GitHub OIDC in CI); guest SSH uses the Packer-generated temporary keypair.
- `reusable-packer-framework-build.yaml` keeps the upstream input contract
  byte-compatible (contract check passes unchanged) and swaps the build path to
  `aws-actions/configure-aws-credentials` + `packer build` on `ubuntu-latest`.
- RHEL 8 example under `examples/packer/rhel-8/` pins the official Red Hat
  owner account (`309956199498`) with a RHEL 8.10 name filter and wires
  `ansible_config` at consumer-owned ansible-framework content (os_bootstrap).
- Validation helpers (`validate_examples.sh` / `.ps1`) adapted: same stub
  Ansible flow, `assert_source_ami_required` replaces the boot_iso guard.

## Verification

- `bash .github/scripts/validate_examples.sh` -> OK (example validates; the
  `source_ami = null` guard fails with the expected message).
- `packer fmt -check -recursive packer/` -> OK.
- `packer init` -> amazon v1.8.2, ansible v1.1.4, git v0.6.5 install cleanly
  against the pinned Packer 1.15.0.
- `python3 tools/check_reusable_workflow_contract.py` -> OK.

## Checks Not Run

- No real AWS build was attempted; `build: true` in the reusable workflow needs
  an OIDC role (`aws_role_to_assume`) configured in the consumer repo.
- Drift Gate, Repo Hygiene, and Security workflows have not run yet (no remote).

## Known Remaining Gaps

- `boot_mode` and `tpm_support` are not part of the contract: the `amazon-ebs`
  builder (CreateImage flow) inherits both from the source AMI. If forcing UEFI
  or NitroTPM becomes a requirement, that is an `ebssurrogate` migration.
- STIG partition-layout controls (separate /home, /tmp, /var, /var/log,
  /var/log/audit) cannot be met on the stock single-root-volume RHEL AMI;
  consumers must track them as documented exceptions or build a
  custom-partitioned source AMI.
- STIG/CIS hardening roles are not yet in ansible-framework; the consumer repo
  currently runs the os_bootstrap dispatcher only.
- `opa_version` remains accepted but unused for upstream contract
  compatibility, as documented in the workflow input description.

## Recommended Next Smallest Task

Push both repositories, configure the GitHub OIDC role and
`AWS_PACKER_FRAMEWORK_ROLE_ARN` / `AWS_REGION` secrets in
`secure-rhel8-ami`, and run the consumer's validate path end-to-end through the
reusable workflow before attempting the first `build: true` AMI build.
