.PHONY: test

IMAGE_NAME := registry.fedoraproject.org/fedora:28
A_P := ansible-playbook --vault-password-file roles/secret/files/ans-vault.txt

oat:
	$(A_P) ./oat.yaml

hops:
	ansible-playbook ./hops.yaml

rye:
	$(A_P) ./rye.yaml

soy:
	$(A_P) --skip-tags "graphical,workstation" ./soy.yaml

jahoda:
	$(A_P) "graphical,workstation" ./jahoda.yaml

test:
	docker run --rm -it -v ${PWD}:/src -w /src $(IMAGE_NAME) ./bootstrap.sh

check-bootstrap:
	docker run --rm -it -v ${PWD}:/src:Z -w /src $(IMAGE_NAME) bash -c ' \
		dnf install -y ansible git && \
		ansible-playbook -vv ./playbook.yaml'
