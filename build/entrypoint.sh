#!/bin/bash

# echo $ANSIBLE_VAULT_PASSWORD >> .vault
# ansible-playbook $1 --vault-password-file .vault
# rm .vault

ansible-playbook $1
