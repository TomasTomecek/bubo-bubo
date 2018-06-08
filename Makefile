.PHONY: test

IMAGE_NAME := registry.fedoraproject.org/fedora:28

oat:
	ansible-playbook ./oat.yaml

rye:
	ansible-playbook ./rye.yaml

soy:
	ansible-playbook --skip-tags "graphical,workstation" ./soy.yaml

jahoda:
	ansible-playbook --skip-tags "graphical,workstation" ./jahoda.yaml

test:
	docker run --rm -it -v ${PWD}:/src -w /src $(IMAGE_NAME) ./bootstrap.sh

check-bootstrap:
	docker run --rm -it -v ${PWD}:/src -w /src $(IMAGE_NAME) bash -c ' \
		dnf install -y ansible git && \
		ansible-playbook -vv ./playbook.yaml'
