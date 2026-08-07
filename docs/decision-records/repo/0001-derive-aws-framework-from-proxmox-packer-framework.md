# ADR-0001: Derive the AWS Framework from proxmox-packer-framework

| Field          | Value                                    |
| -------------- | ---------------------------------------- |
| Status         | Accepted                                 |
| Date           | 2026-08-07                               |
| Authors        | Nick Warila (@NWarila)                   |
| Decision-maker | Nick Warila (sole portfolio maintainer)  |
| Consulted      | None.                                    |
| Informed       | None.                                    |
| Reversibility  | Expensive once consumers pin releases    |
| Review-by      | N/A (Accepted)                           |

## TL;DR

`aws-packer-framework` is derived from
[`proxmox-packer-framework`](https://github.com/nwarila-platform/proxmox-packer-framework)
rather than scaffolded fresh from `NWarila/packer-framework-template`. It mirrors that
repository's conventions byte-for-byte where the concern is platform-neutral (repo hygiene,
validation flow, reusable workflow contract, runner protocol, docs layout) and re-maps the
platform-specific layers onto AWS: the `proxmox-iso` builder becomes `amazon-ebs`, the
externally-owned ISO boundary becomes an owner-scoped **source AMI boundary**, and the
install-template/virtual-CD mechanism becomes an optional **user-data template** rendered with
the same guaranteed template variable contract.

## Context and Problem Statement

The org already operates a mature Proxmox Packer framework with a settled ownership model
(framework owns the builder contract and normalization; consumers own installer templates,
Ansible content, and environment values), a reusable build workflow whose input contract is
enforced by `tools/check_reusable_workflow_contract.py`, and a validation flow exercised by CI
and pre-commit. Building AMIs for AWS needs the same discipline. The question is whether to
derive from the type template directly or from the Proxmox derivative that has accumulated
post-template hardening (source AMI/ISO supply guards, validate-only Ansible stubs, release
evidence shaped for frameworks).

## Decision

Derive from `proxmox-packer-framework` and preserve its structure, naming, and contracts
wherever AWS does not force a difference. Platform mappings:

| Proxmox concern | AWS mapping |
| --- | --- |
| `proxmox-iso` builder | `amazon-ebs` builder |
| `boot_iso` supplied by ISO-manager Terraform | `source_ami` supplied by the caller (pinned `ami_id` or owner-scoped filter) |
| `install_template` rendered onto a virtual CD | optional `user_data_template` rendered into EC2 user data |
| secure-packer-bootstrapper credential generation | Packer-generated temporary EC2 keypair; GitHub OIDC role assumption for CI credentials |
| Proxmox API token secrets | no static credentials; ambient AWS credential chain |
| `disks` / `network_adapters` / EFI / TPM hardware objects | `launch_block_device_mappings` / `vpc_config` / `metadata_options` (`imds_support`); boot mode and NitroTPM are inherited from the source AMI |

Security posture carried over and translated: no bundled media defaults (`source_ami` is
required and unscoped filters are rejected), IMDSv2 enforced by normalized defaults, EBS
encryption on by default, and validation that fails fast at `packer validate` rather than at
build time.

## Consequences

- Consumers of both frameworks see the same runner protocol, reusable workflow input names,
  and repo layout; only the platform variable objects differ.
- Drift Gate continues to verify the org and Packer-template baselines; this repo tracks
  `proxmox-packer-framework` conventions by review rather than by manifest.
- The framework ships no Ansible content and no hardening profiles. STIG/CIS compliance for
  RHEL 8 images is applied by consumer repositories through
  [`ansible-framework`](https://github.com/nwarila-platform/ansible-framework) roles via the
  framework's Ansible provisioner wiring.
