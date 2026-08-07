#!/usr/bin/env bash
set -euo pipefail

repo_root="$(
  cd "$(dirname "${BASH_SOURCE[0]}")/../.." >/dev/null 2>&1
  pwd -P
)"

packer_dir="$repo_root/packer"
tmp_dir="$(mktemp -d)"

cleanup() {
  rm -rf "$tmp_dir"
}

trap cleanup EXIT

stub_playbook="$tmp_dir/validation-playbook.yml"
stub_ansible_playbook="$tmp_dir/ansible-playbook"

# Validation should cover the example surfaces without reintroducing repo-owned
# Ansible content as part of the supported runtime contract.
cat > "$stub_playbook" <<'YAML'
---
- name: Validation-only Ansible stub
  hosts: all
  gather_facts: false
  tasks:
    - name: Emit validation marker
      ansible.builtin.debug:
        msg: validation-only stub
YAML

cat > "$stub_ansible_playbook" <<'SH'
#!/usr/bin/env sh
if [ "$1" = "--version" ]; then
  echo "ansible-playbook [core 2.18.0]"
  exit 0
fi
exit 0
SH

chmod +x "$stub_ansible_playbook"
export PATH="$tmp_dir:$PATH"

create_override_file() {
  local override_file="$1"

  cat > "$override_file" <<EOF
aws_region       = "us-east-1"
deploy_user_name = "ec2-user"

ansible_config = {
  playbook_path     = "${stub_playbook}"
  requirements_path = null
  roles_path        = null
  config_path       = null
  extra_vars        = {}
}
EOF
}

validate_example() {
  local example_name="$1"
  local example_file="$2"
  local override_file="$tmp_dir/${example_name}.pkrvars.hcl"

  create_override_file "$override_file"

  echo "Validating ${example_name}..."
  packer validate \
    -var-file="$example_file" \
    -var-file="$override_file" \
    .
}

assert_source_ami_required() {
  local example_file="$1"
  local override_file="$tmp_dir/source-ami-required.pkrvars.hcl"
  local null_source_ami_file="$tmp_dir/source-ami-null.pkrvars.hcl"
  local expected_message="The source_ami value must be supplied explicitly by the caller."
  local output
  local status

  create_override_file "$override_file"
  cat > "$null_source_ami_file" <<'EOF'
source_ami = null
EOF

  echo "Validating source_ami required guard..."
  set +e
  output="$(
    packer validate \
      -var-file="$example_file" \
      -var-file="$override_file" \
      -var-file="$null_source_ami_file" \
      . 2>&1
  )"
  status="$?"
  set -e

  if [ "$status" -eq 0 ]; then
    echo "::error::packer validate succeeded with source_ami = null" >&2
    exit 1
  fi

  if [[ "$output" != *"$expected_message"* ]]; then
    echo "::error::missing expected source_ami validation message" >&2
    printf '%s\n' "$output" >&2
    exit 1
  fi
}

cd "$packer_dir"
packer init .

validate_example \
  "rhel-8" \
  "$repo_root/examples/packer/rhel-8/rhel-8.pkrvars.hcl"

assert_source_ami_required \
  "$repo_root/examples/packer/rhel-8/rhel-8.pkrvars.hcl"
