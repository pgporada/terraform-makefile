.PHONY: all

all:
	@cat Makefile

init:
	@if [ -z $(ENVIRONMENT) ]; then echo "ENVIRONMENT was not set" ; exit 10 ; fi
	@rm -rf .terraform/*.tf*
	@terraform remote config \
		-backend=S3 \
		-backend-config="region=us-east-1" \
		-backend-config="bucket=$(ENVIRONMENT)-useast1-terraform-state" \
		-backend-config="key=$(ENVIRONMENT).tfstate"
	@terraform remote pull

update:
	@terraform get -update=true &>/dev/null

plan: init update
	@terraform plan -input=false -refresh=true -module-depth=-1 -var-file=environments/$(ENVIRONMENT)/$(ENVIRONMENT).tfvars

plan-destroy: init update
	@terraform plan -input=false -refresh=true -module-depth=-1 -destroy -var-file=environments/$(ENVIRONMENT)/$(ENVIRONMENT).tfvars

show: init
	@terraform show -module-depth=-1

graph:
	@rm -f graph.png
	@terraform graph -draw-cycles -module-depth=-1 | dot -Tpng > graph.png
	@open graph.png

apply: init update
	@terraform apply -input=true -refresh=true -var-file=environments/$(ENVIRONMENT)/$(ENVIRONMENT).tfvars && terraform remote push

#output: init update
output: update
	@if [ -z $(MODULE) ]; then terraform output ; else terraform output -module=$(MODULE) ; fi

destroy: init update
	@terraform destroy -var-file=environments/$(ENVIRONMENT)/$(ENVIRONMENT).tfvars && terraform remote push
