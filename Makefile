# Copyright 2016 Philip G. Porada
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#  http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

.ONESHELL:
SHELL := /bin/bash
.PHONY: help

# Strips 'terraform-' from the folder name and uses this as the storage folder in S3.
# I create all my terraform projects in the following format. terraform-vpc, terraform-my-app, terraform-your-app
BUCKETKEY = $(shell basename "$$(pwd)" | sed 's/terraform-//')

help:
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-30s\033[0m %s\n", $$1, $$2}'

validate: ## Runs `terraform validate` against all the .tf files
	@for i in $$(find -type f -name "*.tf" -exec dirname {} \;); do \
		terraform validate "$$i"; \
		if [ $$? -ne 0 ]; then \
			echo "Failed Terraform file validation on file $${i}"; \
			echo; \
			exit 1; \
		fi; \
	done

set-env:
	@if [ -z $(ENVIRONMENT) ]; then\
		 echo "ENVIRONMENT was not set"; exit 10;\
	 fi
	@echo "\nRemoving existing ENVIRONMENT.tfvars from local directory"
	@find . -maxdepth 1 -type f -name '*.tfvars' ! -name example_ENV.tfvars -exec rm -f {} \;
	@echo "\nPulling fresh $(ENVIRONMENT).tfvars from s3://$(ENVIRONMENT)-useast1-terraform-state/$(BUCKETKEY)/"
	@aws s3 cp s3://$(ENVIRONMENT)-useast1-terraform-state/$(BUCKETKEY)/$(ENVIRONMENT).tfvars .

init: validate set-env
	@rm -rf .terraform/*.tf*
	@terraform remote config \
		-backend=S3 \
		-backend-config="region=us-east-1" \
		-backend-config="bucket=$(ENVIRONMENT)-useast1-terraform-state" \
		-backend-config="key=$(BUCKETKEY)/$(ENVIRONMENT).tfstate" && \
	@terraform remote pull

update:
	@terraform get -update=true 1>/dev/null

plan: init update ## Display all the changes that Terraform is going to make.
	@terraform plan \
		-input=false \
		-refresh=true \
		-module-depth=-1 \
		-var-file=environments/$(ENVIRONMENT)/$(ENVIRONMENT).tfvars \
		-var-file=$(ENVIRONMENT).tfvars

plan-target: init update ## Shows what a plan looks like for applying a specific resource
	@tput setaf 3; tput bold; echo -n "[INFO]   "; tput sgr0; echo "Example to type for the following question: module.rds.aws_route53_record.rds-master"
	@read -p "PLAN target: " DATA &&\
		terraform plan \
			-input=true \
			-refresh=true \
			-var-file=environments/$(ENVIRONMENT)/$(ENVIRONMENT).tfvars \
			-var-file=$(ENVIRONMENT).tfvars \
			-target=$$DATA

plan-destroy: init update ## Creates a destruction plan.
	@terraform plan \
		-input=false \
		-refresh=true \
		-module-depth=-1 \
		-destroy \
		-var-file=environments/$(ENVIRONMENT)/$(ENVIRONMENT).tfvars \
		-var-file=$(ENVIRONMENT).tfvars

show: init
	@terraform show -module-depth=-1

graph: ## Output the `dot` graph of all the built Terraform resources
	@rm -f graph.png
	@terraform graph -draw-cycles -module-depth=-1 | dot -Tpng > graph.png
	@shotwell graph.png

apply: init update ## Apply builds/changes resources. You should ALWAYS run a plan first.
	@terraform apply \
		-input=true \
		-refresh=true \
		-var-file=environments/$(ENVIRONMENT)/$(ENVIRONMENT).tfvars \
		-var-file=$(ENVIRONMENT).tfvars && \
	terraform remote push

apply-target: init update ## Apply a specific resource and any chained resources.
	@tput setaf 3; tput bold; echo -n "[INFO]   "; tput sgr0; echo "Specifically APPLY a piece of Terraform data."
	@tput setaf 3; tput bold; echo -n "[INFO]   "; tput sgr0; echo "Example to type for the following question: module.rds.aws_route53_record.rds-master"
	@tput setaf 1; tput bold; echo -n "[DANGER] "; tput sgr0; echo "You are about to apply a new state."
	@tput setaf 1; tput bold; echo -n "[DANGER] "; tput sgr0; echo "This has the potential to break your infrastructure."
	@read -p "APPLY target: " DATA &&\
		terraform apply \
			-input=true \
			-refresh=true \
			-var-file=environments/$(ENVIRONMENT)/$(ENVIRONMENT).tfvars \
			-var-file=$(ENVIRONMENT).tfvars \
			-target=$$DATA \
		terraform remote push

output: init update ## Display all outputs from the remote state file.
	@echo "Example to type for the module: MODULE=module.rds.aws_route53_record.rds-master"
	@echo
	@if [ -z $(MODULE) ]; then\
		terraform output;\
	 else\
		terraform output -module=$(MODULE);\
	 fi

taint: init update ## Taint a resource for destruction upon next `apply`
	@echo "Tainting involves specifying a module and a resource"
	@read -p "Module: " MODULE && \
		read -p "Resource: " RESOURCE && \
		terraform taint \
			-var-file=environments/$(ENVIRONMENT)/$(ENVIRONMENT).tfvars \
			-var-file=$(ENVIRONMENT).tfvars \
			-module=$$MODULE $$RESOURCE && \
		terraform remote push
	@echo "You will now want to run a plan to see what changes will take place"

destroy: init update ## Destroys everything. There is a prompt before destruction.
	@terraform destroy \
		-var-file=environments/$(ENVIRONMENT)/$(ENVIRONMENT).tfvars \
		-var-file=$(ENVIRONMENT).tfvars && \
	terraform remote push

destroy-target: init update ## Destroy a specific resource. Caution though, this destroys chained resources.
	@echo "Specifically destroy a piece of Terraform data."
	@echo
	@echo "Example to type for the following question: module.rds.aws_route53_record.rds-master"
	@echo
	@read -p "Destroy target: " DATA &&\
		terraform destroy \
		-var-file=environments/$(ENVIRONMENT)/$(ENVIRONMENT).tfvars \
		-var-file=$(ENVIRONMENT).tfvars \
		-target=$$DATA && \
	terraform remote push
