# Overview: terraform-makefile
[![License](https://img.shields.io/badge/license-Apache--2.0-brightgreen.svg)](LICENSE)

This is my [terraform](https://www.terraform.io/) workflow for every terraform project that I use personally/professionaly.

- - - -
# Usage

View a description of Makefile targets with help via the [self-documenting makefile](https://marmelab.com/blog/2016/02/29/auto-documented-makefile.html).

    make

Show a plan from the remote state

    ENVIRONMENT=qa make plan
    ENVIRONMENT=prod make plan

Show root level output

    ENVIRONMENT=qa make output

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

    $ tree -F -l
    terraform-my-project
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
