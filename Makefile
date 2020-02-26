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
.PHONY: apply destroy-backend destroy destroy-target plan-destroy plan plan-target prep
VARS="variables/$(ENV)-$(REGION).tfvars"
CURRENT_FOLDER=$(shell basename "$$(pwd)")
S3_BUCKET="$(ENV)-$(REGION)-yourCompany-terraform"
DYNAMODB_TABLE="$(ENV)-$(REGION)-yourCompany-terraform"
WORKSPACE="$(ENV)-$(REGION)"
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
	@echo "$(BOLD)Verifying that the S3 bucket $(S3_BUCKET) for remote state exists$(RESET)"
	@if ! aws --profile $(AWS_PROFILE) s3api head-bucket --region $(REGION) --bucket $(S3_BUCKET) > /dev/null 2>&1 ; then \
		echo "$(BOLD)S3 bucket $(S3_BUCKET) was not found, creating new bucket with versioning enabled to store tfstate$(RESET)"; \
		aws --profile $(AWS_PROFILE) s3api create-bucket \
			--bucket $(S3_BUCKET) \
			--acl private \
			--region $(REGION) \
			--create-bucket-configuration LocationConstraint=$(REGION) > /dev/null 2>&1 ; \
		aws --profile $(AWS_PROFILE) s3api put-bucket-versioning \
			--bucket $(S3_BUCKET) \
			--versioning-configuration Status=Enabled > /dev/null 2>&1 ; \
		echo "$(BOLD)$(GREEN)S3 bucket $(S3_BUCKET) created$(RESET)"; \
	 else
		echo "$(BOLD)$(GREEN)S3 bucket $(S3_BUCKET) exists$(RESET)"; \
	 fi
	@echo "$(BOLD)Verifying that the DynamoDB table exists for remote state locking$(RESET)"
	@if ! aws --profile $(AWS_PROFILE) dynamodb describe-table --table-name $(DYNAMODB_TABLE) > /dev/null 2>&1 ; then \
		echo "$(BOLD)DynamoDB table $(DYNAMODB_TABLE) was not found, creating new DynamoDB table to maintain locks$(RESET)"; \
		aws --profile $(AWS_PROFILE) dynamodb create-table \
        	--region $(REGION) \
        	--table-name $(DYNAMODB_TABLE) \
        	--attribute-definitions AttributeName=LockID,AttributeType=S \
        	--key-schema AttributeName=LockID,KeyType=HASH \
        	--provisioned-throughput ReadCapacityUnits=5,WriteCapacityUnits=5 > /dev/null 2>&1 ; \
		echo "$(BOLD)$(GREEN)DynamoDB table $(DYNAMODB_TABLE) created$(RESET)"; \
		echo "Sleeping for 10 seconds to allow DynamoDB state to propagate through AWS"; \
		sleep 10; \
	 else
		echo "$(BOLD)$(GREEN)DynamoDB Table $(DYNAMODB_TABLE) exists$(RESET)"; \
	 fi
	@aws ec2 --profile=$(AWS_PROFILE) describe-key-pairs | jq -r '.KeyPairs[].KeyName' | grep "$(ENV)_infra_key" > /dev/null 2>&1; \
	if [ $$? -ne 0 ]; then \
	    echo "$(BOLD)$(RED)EC2 Key Pair $(INFRA_KEY)_infra_key was not found$(RESET)"; \
	    read -p '$(BOLD)Do you want to generate a new keypair? [y/Y]: $(RESET)' ANSWER && \
    	if [ "$${ANSWER}" == "y" ] || [ "$${ANSWER}" == "Y" ]; then \
	        mkdir -p ~/.ssh; \
	        ssh-keygen -t rsa -b 4096 -N '' -f ~/.ssh/$(ENV)_infra_key; \
        	aws ec2 --profile=$(AWS_PROFILE) import-key-pair --key-name "$(ENV)_infra_key" --public-key-material "file://~/.ssh/$(ENV)_infra_key.pub"; \
    	fi; \
	  else \
	      echo "$(BOLD)$(GREEN)EC2 Key Pair $(ENV)_infra_key exists$(RESET)";\
	  fi
	@echo "$(BOLD)Configuring the terraform backend$(RESET)"
	@terraform init \
		-input=false \
		-force-copy \
		-lock=true \
		-upgrade \
		-verify-plugins=true \
		-backend=true \
		-backend-config="profile=$(AWS_PROFILE)" \
		-backend-config="region=$(REGION)" \
		-backend-config="bucket=$(S3_BUCKET)" \
		-backend-config="key=$(ENV)/$(CURRENT_FOLDER)/terraform.tfstate" \
		-backend-config="dynamodb_table=$(DYNAMODB_TABLE)"\
	    -backend-config="acl=private"
	@echo "$(BOLD)Switching to workspace $(WORKSPACE)$(RESET)"
	@terraform workspace select $(WORKSPACE) || terraform workspace new $(WORKSPACE)

plan: prep ## Show what terraform thinks it will do
	@terraform plan \
		-lock=true \
		-input=false \
		-refresh=true \
		-var-file="$(VARS)"

# https://github.com/liamg/tfsec
check-security: prep ## Static analysis of your terraform templates to spot potential security issues.
	@tfsec .

plan-target: prep ## Shows what a plan looks like for applying a specific resource
	@echo "$(YELLOW)$(BOLD)[INFO]   $(RESET)"; echo "Example to type for the following question: module.rds.aws_route53_record.rds-master"
	@read -p "PLAN target: " DATA && \
		terraform plan \
			-lock=true \
			-input=true \
			-refresh=true \
			-var-file="$(VARS)" \
			-target=$$DATA

plan-destroy: prep ## Creates a destruction plan.
	@terraform plan \
		-input=false \
		-refresh=true \
		-destroy \
		-var-file="$(VARS)"

apply: prep ## Have terraform do the things. This will cost money.
	@terraform apply \
		-lock=true \
		-input=false \
		-refresh=true \
		-var-file="$(VARS)"

destroy: prep ## Destroy the things
	@terraform destroy \
		-lock=true \
		-input=false \
		-refresh=true \
		-var-file="$(VARS)"

destroy-target: prep ## Destroy a specific resource. Caution though, this destroys chained resources.
	@echo "$(YELLOW)$(BOLD)[INFO] Specifically destroy a piece of Terraform data.$(RESET)"; echo "Example to type for the following question: module.rds.aws_route53_record.rds-master"
	@read -p "Destroy target: " DATA && \
		terraform destroy \
		-lock=true \
		-input=false \
		-refresh=true \
		-var-file=$(VARS) \
		-target=$$DATA

destroy-backend: ## Destroy S3 bucket and DynamoDB table
	@if ! aws --profile $(AWS_PROFILE) dynamodb delete-table \
		--region $(REGION) \
		--table-name $(DYNAMODB_TABLE) > /dev/null 2>&1 ; then \
			echo "$(BOLD)$(RED)Unable to delete DynamoDB table $(DYNAMODB_TABLE)$(RESET)"; \
	 else
		echo "$(BOLD)$(RED)DynamoDB table $(DYNAMODB_TABLE) does not exist.$(RESET)"; \
	 fi
	@if ! aws --profile $(AWS_PROFILE) s3api delete-objects \
		--region $(REGION) \
		--bucket $(S3_BUCKET) \
		--delete "$$(aws --profile $(AWS_PROFILE) s3api list-object-versions \
						--region $(REGION) \
						--bucket $(S3_BUCKET) \
						--output=json \
						--query='{Objects: Versions[].{Key:Key,VersionId:VersionId}}')" > /dev/null 2>&1 ; then \
			echo "$(BOLD)$(RED)Unable to delete objects in S3 bucket $(S3_BUCKET)$(RESET)"; \
	 fi
	@if ! aws --profile $(AWS_PROFILE) s3api delete-objects \
		--region $(REGION) \
		--bucket $(S3_BUCKET) \
		--delete "$$(aws --profile $(AWS_PROFILE) s3api list-object-versions \
						--region $(REGION) \
						--bucket $(S3_BUCKET) \
						--output=json \
						--query='{Objects: DeleteMarkers[].{Key:Key,VersionId:VersionId}}')" > /dev/null 2>&1 ; then \
			echo "$(BOLD)$(RED)Unable to delete markers in S3 bucket $(S3_BUCKET)$(RESET)"; \
	 fi
	@if ! aws --profile $(AWS_PROFILE) s3api delete-bucket \
		--region $(REGION) \
		--bucket $(S3_BUCKET) > /dev/null 2>&1 ; then \
			echo "$(BOLD)$(RED)Unable to delete S3 bucket $(S3_BUCKET) itself$(RESET)"; \
	 fi
