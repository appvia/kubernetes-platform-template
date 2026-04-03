# Makefile for the clusters

default: all

.PHONY: local clean
local:
	@echo "--> Provisioning development environment (local)"
	@./scripts/make-local.sh --cluster-name dev

all:
	@echo "--> Running all tasks..."
	@$(MAKE) lint
	@$(MAKE) validate
	@$(MAKE) tests
	@$(MAKE) security
	@$(MAKE) format
	@$(MAKE) documentation

dev:
	@echo "--> Provisioning dev cluster..."
	@cd terraform && terraform init
	@cd terraform && terraform apply -auto-approve

dev-destroy:
	@echo "--> Destroying dev cluster..."
	@cd terraform && terraform destroy

destroy-local:
	@echo "--> Destroying development environment..."
	@kind delete cluster --name dev > /dev/null 2>&1 || true

format:
	@echo "--> Formatting Configuration..."
	@make -C terraform format

validate:
	@echo "--> Validating Configuration..."
	@make -C terraform validate

lint:
	@echo "--> Linting Configuration..."
	@$(MAKE) lint-yaml
	@$(MAKE) lint-commits
	@make -C terraform lint

lint-yaml:
	@echo "--> Linking YAML files..."
	@yamllint .

lint-commits:
	@echo "--> Running commitlint against the main branch"
	@command -v commitlint >/dev/null 2>&1 || { echo "commitlint is not installed. Please install it by running 'npm install -g commitlint'"; exit 1; }
	@git log --pretty=format:"%s" origin/main..HEAD | commitlint --from=origin/main

validate-terraform:
	@make -C terraform validate

tests: 
	@echo "--> Running Tests..."
	@make -C terraform tests

documentation:
	@echo "--> Generating Documentation..."
	@make -C terraform documentation

security:
	@echo "--> Running Security Checks..."
	@make -C terraform security

clean:
	@echo "--> Cleaning up..."
	@rm -rf terraform/.terraform
	@rm -rf terraform/.terraform.lock.hcl
