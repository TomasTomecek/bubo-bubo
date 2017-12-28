#!/bin/bash
set -ex
dnf install -y git ansible
cd $HOME
git clone https://github.com/TomasTomecek/bubo-bubo
cd bubo-bubo
ansible-playbook ./playbook.yaml
