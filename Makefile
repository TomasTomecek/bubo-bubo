.PHONY: test

IMAGE_NAME := registry.fedoraproject.org/fedora:27

oat:
	ansible-playbook ./oat.yaml

rye:
	ansible-playbook ./rye.yaml

soy:
	ansible-playbook --skip-tags "graphical,workstation" ./soy.yaml

test:
	docker run --rm -it -v ${PWD}:/src -w /src $(IMAGE_NAME) ./bootstrap.sh
