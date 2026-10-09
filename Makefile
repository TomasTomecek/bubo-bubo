.PHONY: test

IMAGE_NAME := registry.fedoraproject.org/fedora:41
A_P := ansible-playbook -v -e ansible_python_interpreter=/usr/bin/python3 --vault-password-file roles/secret/files/ans-vault.txt

cacao:
	$(A_P) ./cacao.yaml

haskap:
	ansible-playbook -v -e ansible_python_interpreter=/usr/bin/python3 -K ./haskap.yaml

plum:
	ansible-playbook -v -e ansible_python_interpreter=/usr/bin/python3 -K ./plum.yaml

soy:
	$(A_P) --skip-tags "graphical,workstation" ./soy.yaml

batatas:
	ansible-playbook -v -e ansible_python_interpreter=/usr/bin/python3 -K ./batatas.yaml

test:
	docker run --rm -it -v ${PWD}:/src -w /src $(IMAGE_NAME) ./bootstrap.sh

check-bootstrap:
	docker run --rm -it -v ${PWD}:/src:Z -w /src $(IMAGE_NAME) bash -c ' \
		dnf install -y ansible git && \
		ansible-playbook -vv ./playbook.yaml'
