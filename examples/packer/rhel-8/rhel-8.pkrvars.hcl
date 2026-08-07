# ============================================================================================= #
# RHEL 8 — UEFI-preferred, SSH communicator, ansible-framework os_bootstrap provisioning      #
#                                                                                               #
# NOTE: The example region, VPC, and subnet values are placeholders. Downstream repos must      #
# supply placement appropriate for their environment. AMI names are suffixed with a build       #
# timestamp by the framework, so repeated builds never collide.                                 #
#                                                                                               #
# This example produces the STIG/CIS-track RHEL 8 base image: the build runs the                #
# ansible-framework os_bootstrap role (RedHat-family hosts dispatch to RedHat_Rocky_8, whose    #
# strict assertion accepts RHEL/Rocky 8); STIG and CIS hardening roles are layered on by the    #
# consumer's ansible-framework content as they land.                                            #
#                                                                                               #
# NOTE: Cloud AMI builds inherit the source AMI's single-root-volume partition layout. STIG     #
# controls that require separate /home, /tmp, /var, /var/log, and /var/log/audit partitions     #
# cannot be fully satisfied by post-boot hardening alone; track those as documented exceptions  #
# or use a custom-partitioned source AMI.                                                       #
# ============================================================================================= #

# --- Source AMI -------------------------------------------------------------------------- #
# In production, runner repos render this block into an auto-loaded pkrvars file whose diff
# history is the audit trail of which base image each build consumed. See
# docs/explanation/architecture.md#source-ami-boundary. The owner-scoped filter below resolves
# the latest official Red Hat RHEL 8.10 x86_64 AMI (owner 309956199498 is Red Hat's
# commercial AMI account). Pin ami_id instead of a filter for fully reproducible builds.
source_ami = {
  ami_id = null
  owners = ["309956199498"]
  filters = {
    name                = "RHEL-8.10*_HVM-*-x86_64-*-Hourly2-GP3"
    root-device-type    = "ebs"
    virtualization-type = "hvm"
  }
  most_recent = true
}

# --- User Data Template ------------------------------------------------------------------ #
# Points to the cloud-init template shipped with this example. Consumer repos should provide
# their own template path. The template receives the guaranteed template variable contract
# (see docs/reference/template-contract.md).
user_data_template = {
  template_path = "../examples/packer/rhel-8/user-data.pkrtpl.hcl"
  extra_vars    = {}
}

# --- Ansible Configuration --------------------------------------------------------------- #
# Consumer repos import their Ansible roles from ansible-framework and own the playbook that
# composes them. This example assumes ansible-framework is checked out next to this framework
# and the consumer playbook includes the os_bootstrap dispatcher, e.g.:
#
#   - name: Bootstrap every target
#     hosts: all
#     gather_facts: false
#     become: false
#     tasks:
#       - name: Bootstrap this host
#         ansible.builtin.include_role:
#           name: 'os_bootstrap'
#
# config_path points at ansible-framework's ansible.cfg so its
# roles_path = applications:operating_systems resolves the dispatcher and per-OS roles.
ansible_config = {
  playbook_path     = "../../consumer-repo/ansible/playbooks/os-bootstrap.yml"
  requirements_path = null
  roles_path        = null
  config_path       = "../../ansible-framework/ansible.cfg"
  extra_vars        = {}
}

# --- Packer Image ------------------------------------------------------------------------ #
packer_image = {

  # Connection Settings
  communicator                 = "ssh"
  ssh_interface                = "public_ip"
  ssh_timeout                  = "15m"
  winrm_timeout                = null
  winrm_port                   = null
  winrm_use_ssl                = null
  winrm_insecure               = null
  winrm_use_ntlm               = null
  winrm_transport              = null
  winrm_server_cert_validation = null

  # Template Metadata
  os_language = "en_US"
  os_keyboard = "us"
  os_timezone = "UTC"
  os_family   = "linux"
  os_name     = "rhel"
  os_version  = "8"

  # General Settings
  region          = "us-east-1"
  ami_name        = "rhel-8"
  ami_description = "RHEL 8 AMI built with Packer (STIG/CIS hardening track)"
  ami_regions     = []
  ami_users       = []
  ami_org_arns    = []
  tags = {
    Name       = "rhel-8"
    OSFamily   = "linux"
    OSName     = "rhel"
    OSVersion  = "8"
    Hardening  = "stig-cis"
    ManagedBy  = "aws-packer-framework"
    Repository = "nwarila-platform/aws-packer-framework"
  }
  run_tags = {
    Name      = "packer-build-rhel-8"
    ManagedBy = "aws-packer-framework"
  }
  snapshot_tags = {
    Name      = "rhel-8"
    ManagedBy = "aws-packer-framework"
  }

  # Build Instance
  instance_type        = "t3.medium"
  iam_instance_profile = null
  ebs_optimized        = true

  # AMI Settings
  ena_support           = true
  sriov_support         = false
  imds_support          = "v2.0"
  encrypt_boot          = true
  kms_key_id            = null
  force_deregister      = false
  force_delete_snapshot = false

}

launch_block_device_mappings = [
  {
    device_name           = "/dev/sda1"
    volume_size           = 30
    volume_type           = "gp3"
    iops                  = 3000
    throughput            = 125
    encrypted             = true
    kms_key_id            = null
    delete_on_termination = true
  }
]

ami_block_device_mappings = []

# NOTE: temporary_security_group_source_cidrs = ["0.0.0.0/0"] is an EXCEPTION for bootstrap
# builds in a default VPC. Production runner repos should scope this to the CI egress CIDR or
# use ssh_interface = "session_manager" with an instance profile and no inbound rules at all.
vpc_config = {
  vpc_id                                = null
  subnet_id                             = null
  security_group_ids                    = null
  associate_public_ip_address           = true
  temporary_security_group_source_cidrs = ["0.0.0.0/0"]
}

metadata_options = {
  http_endpoint               = "enabled"
  http_tokens                 = "required"
  http_put_response_hop_limit = 1
  instance_metadata_tags      = "disabled"
}
