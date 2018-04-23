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
.SHELL := /bin/bash
.PHONY: plan apply destroy prep help set-env
VARS="variables/$(REGION)-$(ENV).tfvars"
CURRENT_FOLDER=$(shell basename "$$(pwd)")
BOLD=$(shell tput bold)
RED=$(shell tput setaf 1)
RESET=$(shell tput sgr0)

help:
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-30s\033[0m %s\n", $$1, $$2}'

set-env:
	@if [ -z $(ENV) ]; then\
		echo "$(BOLD)$(RED)ENV was not set$(RESET)"; \
		ERROR=1; \
	 fi
	#####
	@if [ -z $(REGION) ]; then\
		echo "$(BOLD)$(RED)REGION was not set$(RESET)"; \
		ERROR=1; \
	 fi
	#####
	@if [ -z $(AWS_PROFILE) ]; then\
		echo "$(BOLD)$(RED)AWS_PROFILE was not set.$(RESET)"; \
		ERROR=1; \
	 fi
	#####
	@if [ ! -z $${ERROR} ] && [ $${ERROR} -eq 1 ]; then
		echo "$(BOLD)Example usage: \`AWS_PROFILE=whatever ENV=demo REGION=us-east-2 make plan\`$(RESET)"; \
		exit 1; \
	 fi
	#####c
	@if [ ! -f "$(VARS)" ]; then \
		echo "$(BOLD)$(RED)Could not find variables file: $(VARS)$(RESET)"; \
		exit 1; \
	 fi

prep: set-env ## Prepare a new workspace (environment) if needed, configure the tfstate backend, update any modules, and switch to the workspace
	@echo "$(BOLD)Verifying that the S3 bucket remote state bucket exists$(RESET)"
	@aws --profile $(AWS_PROFILE) s3api head-bucket --region $(REGION) --bucket $(REGION)-terraform > /dev/null 2>&1
	@if [ $$? -ne 0 ]; then \
		echo "$(BOLD)S3 Bucket was not found, creating new bucket with versioning enabled to store tfstate$(RESET)"; \
		aws --profile $(AWS_PROFILE) s3api create-bucket \
			--bucket $(REGION)-terraform \
			--acl private \
			--region $(REGION) \
			--create-bucket-configuration LocationConstraint=$(REGION); \
		echo; \
		aws --profile $(AWS_PROFILE) s3api put-bucket-versioning \
			--bucket $(REGION)-terraform \
			--versioning-configuration Status=Enabled; \
	 fi
	#####
	@echo "$(BOLD)Configuring the terraform backend$(RESET)"
	@echo "yes" | terraform init \
		-backend-config="profile=$(AWS_PROFILE)" \
		-backend-config="region=$(REGION)" \
		-backend-config="bucket=$(REGION)-terraform" \
		-backend-config="key=$(CURRENT_FOLDER)/$(ENV)/terraform.tfstate"
	#####
	@if [ ! -d terraform.tfstate.d/aws_$(REGION) ]; then \
		echo "$(BOLD)Configuring the terraform workspace$(RESET)"; \
		terraform workspace new aws_$(REGION)_$(ENV); \
	 fi
	#####
	@echo "$(BOLD)Switching to workspace $(REGION)_$(ENV)$(RESET)"
	@echo "yes" | terraform workspace select aws_$(REGION)_$(ENV)
	#####
	@echo "$(BOLD)Updating TF modules$(RESET)"
	@terraform get -update=true
	@echo

plan: prep ## Show what terraform thinks it will do
	@terraform plan -var-file="$(VARS)" -lock=false

plan-target: prep ## Shows what a plan looks like for applying a specific resource
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
		-var-file=$(VARS) \
		-lock=false

apply: prep ## Have terraform do the things. This will cost money.
	@terraform apply -var-file="$(VARS)" -lock=false

destroy: prep ## Destroy the things
	@terraform destroy -var-file="$(VARS)" -lock=false

destroy-target: prep ## Destroy a specific resource. Caution though, this destroys chained resources.
	@echo "Specifically destroy a piece of Terraform data."
	@echo
	@echo "Example to type for the following question: module.rds.aws_route53_record.rds-master"
	@echo
	@read -p "Destroy target: " DATA &&\
		terraform destroy \
		-var-file=$(VARS) \
		-target=$$DATA \
        -lock=false
