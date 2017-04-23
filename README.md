# Overview: terraform-makefile
![TF](https://img.shields.io/badge/Supports%20Terraform%20Version-%3E%3D0.9.3-blue.svg)
[![License](https://img.shields.io/badge/license-Apache--2.0-brightgreen.svg)](LICENSE)

This is my [terraform](https://www.terraform.io/) workflow for every terraform project that I use personally/professionaly. If you've never heard of Terraform, may I suggest [checking out my Ansible role](https://github.com/pgporada/ansible-role-terraform) to download, verify, and install Terraform for you!

- - - -

# Upgrading from Terraform 0.8.x to 0.9.x and using this project

[You will need to follow this doc](https://www.terraform.io/docs/backends/legacy-0-8.html) to prep your own Terraform code to function with this project.


- - - -
# Usage

View a description of Makefile targets with help via the [self-documenting makefile](https://marmelab.com/blog/2016/02/29/auto-documented-makefile.html).

    $ make
    apply                          Apply builds/changes resources. You should ALWAYS run a plan first.
    apply-target                   Apply a specific resource and any chained resources.
    destroy                        Destroys everything. There is a prompt before destruction.
    destroy-target                 Destroy a specific resource. Caution though, this destroys chained resources.
    graph                          Output the `dot` graph of all the built Terraform resources
    output                         Display all outputs from the remote state file.
    plan-destroy                   Creates a destruction plan.
    plan                           Display all the changes that Terraform is going to make.
    plan-target                    Shows what a plan looks like for applying a specific resource
    taint                          Taint a resource for destruction upon next `apply`
    validate                       Runs `terraform validate` against all the .tf files

* Before each target, several private Makefile functions run to configure the remote state backend, `validate`,`set-env`, and `init`. You should never have to run these yourself.

Show a plan from the remote state

    ENVIRONMENT=qa make plan

    $ ENVIRONMENT=qa make plan
	Removing existing ENVIRONMENT-TIER.tfvars from local directory

	Pulling fresh qa.tfvars from s3://qa-useast1-terraform-state/bastion/
	download: s3://qa-useast1-terraform-state/bastion/qa.tfvars to ./qa.tfvars
	Initialized blank state with remote state enabled!
	Remote state configured and pulled.
	Local and remote state in sync
	Refreshing Terraform state in-memory prior to plan...
	The refreshed state will be used to calculate this plan, but
	will not be persisted to local or remote state storage.

	-/+ module.bastion.aws_instance.bastion
    ami:                               "ami-61ce6c77" => "ami-35ab0823" (forces new resource)
    associate_public_ip_address:       "true" => "<computed>"
    availability_zone:                 "us-east-1a" => "<computed>"
    ebs_block_device.#:                "0" => "<computed>"
    ephemeral_block_device.#:          "0" => "<computed>"
    iam_instance_profile:              "qa-bastion-instance-profile" => "qa-bastion-instance-profile"
    instance_state:                    "running" => "<computed>"
    instance_type:                     "t2.micro" => "t2.micro"
    ipv6_addresses.#:                  "0" => "<computed>"
    key_name:                          "qa_useast1_ec2key_bastion" => "qa_useast1_ec2key_bastion"
    network_interface_id:              "eni-d00c2017" => "<computed>"
    placement_group:                   "" => "<computed>"
    private_dns:                       "ip-10-10-10-24.ec2.internal" => "<computed>"
    private_ip:                        "10.10.10.24" => "<computed>"
    public_dns:                        "ec2-52.52.52.52.compute-1.amazonaws.com" => "<computed>"
    public_ip:                         "52.52.52.52" => "<computed>"
    root_block_device.#:               "1" => "<computed>"
    security_groups.#:                 "0" => "<computed>"
    source_dest_check:                 "true" => "true"
    subnet_id:                         "subnet-184a8440" => "subnet-184a8440"
    tags.%:                            "6" => "6"
    tags.ENV:                          "qa" => "qa"
    tags.Name:                         "qa_useast1_bastion" => "qa_useast1_bastion"
    tags.ROLES:                        "bastion" => "bastion"
    tags.TERRAFORM:                    "true" => "true"
    tags.TIER:                         "ga" => "ga"
    tags.TYPE:                         "bastion" => "bastion"
    tenancy:                           "default" => "<computed>"
    user_data:                         "1d902c0382fe19b53225a527fdc7bc95cfed875T" => "1d902c0382fe19b53225a527fdc7bc95cfed875T"
    vpc_security_group_ids.#:          "1" => "1"
    vpc_security_group_ids.1449472535: "sg-305ea24b" => "sg-305ea24b"

	~ module.bastion.aws_route53_record.bastion-priv
    records.#: "" => "<computed>"

	~ module.bastion.aws_route53_record.bastion-pub
    records.#: "" => "<computed>"

	Plan: 1 to add, 2 to change, 1 to destroy.

Show root level output

    ENVIRONMENT=qa make output
	# Alternatively once you've run the make output, you can just run
	terraform output

Output a module

    MODULE=network ENVIRONMENT=qa make output

Output a nested module

    MODULE=network.nat ENVIRONMENT=qa make output

Plan a specific module

	ENVIRONMENT=prod make plan-target

Plan it all

	ENVIRONMENT=prod make plan

- - - -
# Example Terraform project layout

Tree output of a Terraform module I create

    $ tree -F -l
    terraform-bastion
    ├── qa.tfvars                 <========= This comes from S3
    ├── environments/
    │   └── qa/                   <========= This stays in the git repo
    │       └── qa.tfvars
    ├── example_ENV.tfvars
    ├── main.tf
    ├── Makefile
    ├── .gitignore
    ├── .git/
    ├── modules/
    │   └── bastion/
    │       ├── bastion.tf
    │       └── init.sh
    ├── README.md
    └── LICENSE

            5 directories, 10 files

Example `main.tf` inside the tree

    variable "region" {}

    variable "env" {
      default = "qa"
    }
    variable "key_path" {}
    variable "key_name" {}
    variable "ec2_bastion_instance_type" {}
    variable "ec2_bastion_user" {}

    terraform {
      required_version = ">= 0.8.8"
    }

    provider "aws" {
      region              = "${var.region}"
      profile             = "${var.env}"
      allowed_account_ids = ["YOUR_ACCOUNT_ID"]
    }

    data "terraform_remote_state" "vpc" {
      backend = "s3"

      config {
        region     = "${var.region}"
        bucket     = "qa-useast1-terraform-state"
        key        = "bastion/${var.env}.tfstate"
        profile    = "${var.env}"
        acl        = "private"
      }
    }

    module "bastion" {
      source           = "modules/bastion"
      env              = "${var.env}"
      region           = "${var.region}"
      instance_type    = "${var.ec2_bastion_instance_type}"
      bastion_key_name = "${var.key_name}"
      bastion_key_path = "${var.key_path}"
      vpc_id           = "${data.terraform_remote_state.vpc.vpc_id}"
      vpc_cidr         = "${data.terraform_remote_state.vpc.vpc_cidr}"
      subnet_ids       = "${data.terraform_remote_state.vpc.public_subnet_ids}"
      shell_username   = "${var.ec2_bastion_user}"
    }

    output "environment" {
      value = "${var.env}"
    }

    output "bastion_public_ip" {
      value = "${module.bastion.public_ip}"
    }

    output "bastion_private_ip" {
      value = "${module.bastion.private_ip}"
    }

    output "bastion_user" {
      value = "${var.ec2_bastion_user}"
    }

    output "bastion_ami_image_id" {
      value = "${module.bastion.ami_image_id}"
    }

    output "bastion_ami_creation_date" {
      value = "${module.bastion.ami_creation_date}"
    }

    output "bastion_ami_name" {
      value = "${module.bastion.ami_name}"
    }

- - - -
# Considerations

* The terraform `.tfvars` files need to be present in S3 prior to using this. If you don't want to initially store variables in S3, simple remove each `-var-file=$(ENVIRONMENT).tfvars` line from `Makefile`
* Each time this makefile is used, the remote state will be pulled from the backend onto your machine. This can result in slightly longer iteration times.
* There is no locking mechanism, so communication between team members using this is critical.
* The makefile uses `.ONESHELL` which is a feature of gmake. OSX users may need to `brew install gmake`.
* To use `ENVIRONMENT=qa make graph`, you will need to install `dot` via your systems package manager.
* You should configure [remote state encryption for S3 via KMS](https://www.terraform.io/docs/state/remote/s3.html) via `encrypt` and `kms_key_id`.

- - - -
# Author Info and License

![Apache-2.0](LICENSE)

(C) [Philip Porada](https://github.com/pgporada/) - philporada@gmail.com
