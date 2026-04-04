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
	@make -C terraform init
	@make -C terraform environment ENVIRONMENT=dev

dev-destroy:
	@echo "--> Destroying dev cluster..."
	@make -C terraform environment-destroy ENVIRONMENT=dev

destroy-local:
	@echo "--> Destroying development environment..."
	@kind delete cluster --name dev > /dev/null 2>&1 || true

format:
	@echo "--> Formatting Configuration..."
	@make -C terraform format

validate:
	@echo "--> Validating Configuration..."
	@$(MAKE) validate-terraform

validate-terraform:
	@echo "--> Validating GitHub Actions..."
	@make -C terraform validate

lint:
	@echo "--> Linting Configuration..."
	@$(MAKE) lint-yaml
	@$(MAKE) lint-actions
	@$(MAKE) lint-terraform
	@$(MAKE) lint-schemas

lint-yaml:
	@echo "--> Linking YAML files..."
	@yamllint .

lint-schemas:
	@echo "--> Validating Definitions..."
	@scripts/validate-schema.sh

lint-actions:
	@echo "--> Linting GitHub Actions..."
	@if command -v actionlint > /dev/null 2>&1; then \
		actionlint -no-color; \
	else \
		echo "actionline is not installed. Please install it to lint YAML files."; \
		exit 1; \
	fi

lint-terraform:
	@echo "--> Linting Terraform files..."
	@make -C terraform lint

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
	@kind delete cluster --name dev > /dev/null 2>&1 || true
