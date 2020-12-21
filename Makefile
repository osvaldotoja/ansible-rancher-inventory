all: help

prep: ## check requirements
	@./infra.sh prep

create: ## create infra
	@./infra.sh create

destroy: ## destroy infra
	@./infra.sh destroy

test: ## run test
	@./infra.sh test

.PHONY: build
build: ## build local ansible image
	@docker pull alpine:3.11
	@docker build build -t local-ansible:latest

.PHONY: lint
lint: ## lint infra.sh script
	@docker run --rm -v "$(PWD):/mnt" koalaman/shellcheck:stable  infra.sh
	@docker run --rm --volume "$(PWD)":/ansible -w /ansible --entrypoint /usr/bin/ansible-lint local-ansible playbook.yml

graph: ## ansible-inventory --graph
	@docker run -it --rm -e RANCHER_BEARER_TOKEN=$(shell cat .config/apitoken) -e RANCHER_HOST="$(shell cat .config/rancher_url)" -e PYTHONWARNINGS="ignore:Unverified HTTPS request" --volume "$(PWD)":/ansible -w /ansible --entrypoint /usr/bin/ansible-inventory local-ansible --graph   

sh: ## ansible-inventory --graph
	# @docker run -it --rm -e RANCHER_BEARER_TOKEN=$(shell cat .config/apitoken) -e RANCHER_HOST="$(shell cat .config/rancher_url)" -e PYTHONWARNINGS="ignore:Unverified HTTPS request" --volume "$(PWD)":/ansible -w /ansible local-ansible bash
	@docker run -it --rm -e RANCHER_BEARER_TOKEN=$(shell cat .config/apitoken) -e RANCHER_HOST="$(shell cat .config/rancher_url)" -e PYTHONWARNINGS="ignore:Unverified HTTPS request" --volume "$(PWD)":/ansible -w /ansible --entrypoint /bin/bash local-ansible

play: ## ansible-playbook playbook.yaml
	@docker run -it --rm -e RANCHER_BEARER_TOKEN=$(shell cat .config/apitoken) -e RANCHER_HOST="$(shell cat .config/rancher_url)" -e PYTHONWARNINGS="ignore:Unverified HTTPS request" --volume "$(PWD)":/ansible -w /ansible local-ansible playbook.yml

.PHONY: help
help:
	@grep -E '^[0-9a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) \
		| awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-30s\033[0m %s\n", $$1, $$2}'
