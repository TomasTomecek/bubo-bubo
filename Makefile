.PHONY: test

IMAGE_NAME := registry.fedoraproject.org/fedora:41
# Full playbooks need root (packages/secret/common/root-dotfiles), so -K
# prompts for the sudo password interactively. No passwordless sudo is used.
A_P := ansible-playbook -v -e ansible_python_interpreter=/usr/bin/python3 --vault-password-file roles/secret/files/ans-vault.txt -K

cacao:
	$(A_P) ./cacao.yaml

haskap:
	$(A_P) ./haskap.yaml

plum:
	$(A_P) ./plum.yaml

soy:
	$(A_P) --skip-tags "graphical,workstation" ./soy.yaml

batatas:
	$(A_P) ./batatas.yaml

# User-level daily sync (dotfiles only, no root, no vault). Run by the
# sync-configuration wrapper; safe to run headless.
sync:
	ansible-playbook -v -e ansible_python_interpreter=/usr/bin/python3 ./sync.yaml

test:
	docker run --rm -it -v ${PWD}:/src -w /src $(IMAGE_NAME) ./bootstrap.sh

check-bootstrap:
	docker run --rm -it -v ${PWD}:/src:Z -w /src $(IMAGE_NAME) bash -c ' \
		dnf install -y ansible git && \
		ansible-playbook -vv ./playbook.yaml'
