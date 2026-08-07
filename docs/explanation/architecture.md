# Architecture

## Data-Driven Normalization Pattern

The framework uses a three-layer data flow:

1. **Consumer inputs** (`.pkrvars.hcl`) define environment-specific values
2. **`locals.pkr.hcl`** normalizes inputs with `coalesce()` defaults, assembles the
   template variable contract, and renders the optional user-data template
3. **`source.pkr.hcl`** consumes normalized locals to configure the Amazon EBS source

This pattern lets consumers override only what differs from the defaults while ensuring
every build produces a structurally consistent AMI.

## User-Data Template Mechanism

The framework uses a generic `user_data_template` variable instead of OS-specific branching.
Consumer repos provide:

- `template_path` — path to a `.pkrtpl.hcl` file (cloud-init user data, EC2Launch bootstrap, etc.)
- `extra_vars` — OS-specific variables merged into the render context

The framework renders the template with the guaranteed [template variable contract](../reference/template-contract.md)
and passes the result as EC2 user data to the build instance. When `user_data_template` is
null, no user data is sent and the source AMI's stock first-boot behavior is used — unlike
ISO installs, cloud images already boot to a reachable SSH user, so the bootstrap layer is
optional rather than load-bearing.

This design supports any first-boot mechanism (cloud-init, EC2Launch v2, Ignition)
without framework changes. User data is readable from the instance metadata service for the
life of the build instance; the contract never routes secrets through it.

## Surrogate Path (Custom Partition Layouts)

The `amazon-ebs` source registers the AMI from the build instance's root volume, so the image
inherits the source AMI's partition layout. For layouts the source AMI cannot provide — the
motivating case is STIG-mandated separate `/home`, `/tmp`, `/var`, `/var/log`, and
`/var/log/audit` filesystems — the framework ships a second source, `amazon-ebssurrogate`,
sharing the full variable contract plus one addition (`var.surrogate`, the blank volume's
device name, size, and encryption).

The flow mirrors the Proxmox framework's Kickstart ownership split: the framework owns the
builder mechanics (boot from `source_ami`, attach the blank surrogate volume, register the AMI
from it via RegisterImage); the consumer owns the layout content — an Ansible play that runs
after configuration, partitions the surrogate volume, copies the configured root filesystem
into it, and installs the bootloader. Because Ansible runs against the booted build instance
*before* the copy, its changes land in the registered image.

Both sources always validate; a build selects one explicitly:

```bash
packer build -only=amazon-ebssurrogate.packer_image .
```

## Framework-Consumer Boundary

**Framework owns:**

- AWS API integration and build-instance lifecycle (via the `amazon-ebs` builder)
- The shared Packer variable contract (`variables.pkr.hcl`, `locals.pkr.hcl`)
- Communicator wiring (temporary EC2 keypair SSH, WinRM transport, timeout management)
- Security defaults and override points (IMDSv2 enforcement, EBS encryption, owner-scoped
  source AMI resolution)
- Build pipeline orchestration (`builds.pkr.hcl`, `source.pkr.hcl`)
- Template variable contract definition
- Maintained example inputs for RHEL 8

**Consumer repos own:**

- Configuration management (Ansible playbooks, roles, Galaxy requirements)
- User-data templates (cloud-init, EC2Launch)
- Environment-specific values (regions, VPC/subnet placement, instance types, tags)
- Source AMI pins and their audit trail

The default shared source for Ansible content is
[ansible-framework](https://github.com/nwarila-platform/ansible-framework).

## Source AMI Boundary

This framework does not choose, discover, or default base images. The source AMI is owned by
the caller, mirroring the ISO lifecycle boundary in
[`proxmox-packer-framework`](https://github.com/nwarila-platform/proxmox-packer-framework):
there, runner repos pin ISO media through Terraform; here, runner repos pin the base AMI
directly in committed pkrvars.

The integration contract is one variable this framework declares in
[`packer/variables.pkr.hcl`](../../packer/variables.pkr.hcl):

- `source_ami` — typed object. Either a pinned `ami_id`, or `filters` plus a non-empty
  `owners` list.

Two validate-time guards enforce the boundary:

1. `source_ami` may not be null — builds without an explicit base image fail at validate
   time, which is intentional; there is no inferred fallback.
2. Filter-based resolution must be owner-scoped — an unscoped filter could resolve a
   look-alike AMI published by an untrusted account, so it is rejected.

Recommended runner-repo flow:

1. The runner repo commits a pkrvars file containing the `source_ami` object literal — the
   diff history is the long-lived audit trail of which base image each build consumed.
2. The runner repo's CI calls this framework's reusable workflow with `var_file:` pointing at
   the committed file.
3. Filter-based pins (`owners` + name pattern + `most_recent`) track a vendor's patch stream;
   `ami_id` pins are fully reproducible. Choose per image line and record the choice.

## Credential Model

There is no AWS analog of the Proxmox API token variables, and no
secure-packer-bootstrapper stage:

- **AWS credentials** come from the ambient credential chain (GitHub OIDC role assumption in
  CI, SSO/instance profiles locally) or the optional `aws_profile` / `aws_assume_role`
  variables. Static access keys are deliberately not part of the variable contract.
- **Guest credentials** are a Packer-generated temporary EC2 keypair, discarded when the
  build instance terminates. Privilege escalation uses the source AMI's passwordless sudo
  grant for its cloud-init default user (`ec2-user` on RHEL), so no password, hash, or key
  material flows through Packer variables for Linux builds.

## Packer Subdirectory Layout

All Packer HCL files live under `packer/` rather than the repository root. This is a
deliberate choice because the repo also contains examples, documentation, CI/CD
configuration, and editor settings that are not Packer HCL files. Packer parses all
`.pkr.hcl` files in the directory passed to `packer build`, so the subdirectory layout
is functionally equivalent to root placement.

CI workflows and README instructions reference this path consistently via
`working-directory: packer/`.

## File Responsibilities

| File | Purpose |
|------|---------|
| `packer.pkr.hcl` | Packer version constraint and plugin declarations |
| `variables.pkr.hcl` | Input variable declarations (consumer contract surface) |
| `locals.pkr.hcl` | Variable normalization, template var contract, user-data rendering |
| `source.pkr.hcl` | Amazon EBS source definition with dynamic device/filter blocks |
| `builds.pkr.hcl` | Build definition with consumer-driven Ansible provisioner and manifest |
| `data.pkr.hcl` | Git data source for build metadata |
