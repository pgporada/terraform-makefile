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
.SHELL := /usr/bin/bash
.PHONY: plan apply destroy prep help set-env
VARS="variables/$(REGION)-$(ENV).tfvars"
CURRENT_FOLDER=$(shell basename "$$(pwd)")
BOLD=$(shell tput bold)
RED=$(shell tput setaf 1)
GREEN=$(shell tput setaf 2)
YELLOW=$(shell tput setaf 3)
RESET=$(shell tput sgr0)

help:
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-30s\033[0m %s\n", $$1, $$2}'

set-env:
	@if [ -z $(ENV) ]; then \
		echo "$(BOLD)$(RED)ENV was not set$(RESET)"; \
		ERROR=1; \
	 fi

	@if [ -z $(REGION) ]; then \
		echo "$(BOLD)$(RED)REGION was not set$(RESET)"; \
		ERROR=1; \
	 fi

	@if [ -z $(AWS_PROFILE) ]; then \
		echo "$(BOLD)$(RED)AWS_PROFILE was not set.$(RESET)"; \
		ERROR=1; \
	 fi

	@if [ ! -z $${ERROR} ] && [ $${ERROR} -eq 1 ]; then \
		echo "$(BOLD)Example usage: \`AWS_PROFILE=whatever ENV=demo REGION=us-east-2 make plan\`$(RESET)"; \
		exit 1; \
	 fi

	@if [ ! -f "$(VARS)" ]; then \
		echo "$(BOLD)$(RED)Could not find variables file: $(VARS)$(RESET)"; \
		exit 1; \
	 fi

prep: set-env ## Prepare a new workspace (environment) if needed, configure the tfstate backend, update any modules, and switch to the workspace
	@echo "$(BOLD)Verifying that the S3 bucket remote state bucket exists$(RESET)"
	@if ! aws --profile $(AWS_PROFILE) s3api head-bucket --region $(REGION) --bucket $(ENV)-$(REGION) > /dev/null 2>&1 ; then \
		echo "$(BOLD)S3 Bucket was not found, creating new bucket with versioning enabled to store tfstate$(RESET)"; \
		aws --profile $(AWS_PROFILE) s3api create-bucket \
			--bucket $(ENV)-$(REGION) \
			--acl private \
			--region $(REGION) \
			--create-bucket-configuration LocationConstraint=$(REGION) > /dev/null 2>&1 ; \
		aws --profile $(AWS_PROFILE) s3api put-bucket-versioning \
			--bucket $(ENV)-$(REGION) \
			--versioning-configuration Status=Enabled > /dev/null 2>&1 ; \
		echo "$(BOLD)$(GREEN)Bucket created$(RESET)"; \
	 fi
	@echo "$(BOLD)Verifying that the DynamoDB table exists$(RESET)"
	@if ! aws --profile $(AWS_PROFILE) dynamodb describe-table --table-name $(ENV)-$(REGION) > /dev/null 2>&1 ; then \
		echo "$(BOLD)DynamoDB table was not found, creating new DynamoDB table to maintain locks$(RESET)"; \
		aws --profile $(AWS_PROFILE) dynamodb create-table \
        	--region $(REGION) \
        	--table-name $(ENV)-$(REGION) \
        	--attribute-definitions AttributeName=LockID,AttributeType=S \
        	--key-schema AttributeName=LockID,KeyType=HASH \
        	--provisioned-throughput ReadCapacityUnits=5,WriteCapacityUnits=5 > /dev/null 2>&1 ; \
		echo "$(BOLD)$(GREEN)DynamoDB table created$(RESET)"; \
	 fi

	@echo "Sleeping awhile" ; sleep 10

	@echo "$(BOLD)Configuring the terraform backend$(RESET)"
	@terraform init \
		-input=false \
		-force-copy \
		-backend=true \
		-backend-config="profile=$(AWS_PROFILE)" \
		-backend-config="region=$(REGION)" \
		-backend-config="bucket=$(ENV)-$(REGION)" \
		-backend-config="key=$(CURRENT_FOLDER)/$(ENV)/terraform.tfstate" \
		-backend-config="dynamodb_table=$(ENV)-$(REGION)"

	@echo "$(BOLD)Switching to workspace $(ENV)$(RESET)"
	@terraform workspace select $(ENV) || terraform workspace new $(ENV)

	@echo "$(BOLD)Updating TF modules$(RESET)"
	@terraform get -update=true
	@echo

plan: prep ## Show what terraform thinks it will do
	@terraform plan \
		-input=false \
		-refresh=true \
		-var-file="$(VARS)"

plan-target: prep ## Shows what a plan looks like for applying a specific resource
	@echo "$(YELLOW)$(BOLD)[INFO]   $(RESET)"; echo "Example to type for the following question: module.rds.aws_route53_record.rds-master"
	@read -p "PLAN target: " DATA && \
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
		-destroy \
		-var-file=$(VARS)

apply: prep ## Have terraform do the things. This will cost money.
	@terraform apply \
		-auto-approve \
		-input=false \
		-refresh=true \
		-var-file="$(VARS)"

destroy: prep ## Destroy the things
	@terraform destroy \
		-auto-approve \
		-input=false \
		-refresh=true \
		-var-file="$(VARS)"

destroy-target: prep ## Destroy a specific resource. Caution though, this destroys chained resources.
	@echo "$(YELLOW)$(BOLD)[INFO] Specifically destroy a piece of Terraform data.$(RESET)"; echo "Example to type for the following question: module.rds.aws_route53_record.rds-master"
	@read -p "Destroy target: " DATA && \
		terraform destroy \
		-auto-approve \
		-input=false \
		-refresh=true \
		-var-file=$(VARS) \
		-target=$$DATA

destroy-backend: ## Destroy S3 bucket and DynamoDB table
	@if ! aws --profile $(AWS_PROFILE) dynamodb delete-table \
		--region $(REGION) \
		--table-name $(ENV)-$(REGION) > /dev/null 2>&1 ; then \
			echo "Unable to delete DynamoDB table"; \
	 fi

	@if ! aws --profile $(AWS_PROFILE) s3api delete-objects \
		--region $(REGION) \
		--bucket $(ENV)-$(REGION) \
		--delete "$$(aws --profile $(AWS_PROFILE) s3api list-object-versions \
						--region $(REGION) \
						--bucket $(ENV)-$(REGION) \
						--output=json \
						--query='{Objects: Versions[].{Key:Key,VersionId:VersionId}}')" > /dev/null 2>&1 ; then \
			echo "Unable to delete object in S3 bucket"; \
	 fi

	@if ! aws --profile $(AWS_PROFILE) s3api delete-objects \
		--region $(REGION) \
		--bucket $(ENV)-$(REGION) \
		--delete "$$(aws --profile $(AWS_PROFILE) s3api list-object-versions \
						--region $(REGION) \
						--bucket $(ENV)-$(REGION) \
						--output=json \
						--query='{Objects: DeleteMarkers[].{Key:Key,VersionId:VersionId}}')" > /dev/null 2>&1 ; then \
			echo "Unable to delete object in S3 bucket"; \
	 fi

	@if ! aws --profile $(AWS_PROFILE) s3api delete-bucket \
		--region $(REGION) \
		--bucket $(ENV)-$(REGION) > /dev/null 2>&1 ; then \
			echo "Unable to delete S3 bucket itself"; \
	 fi
