.PHONY: test

IMAGE_NAME := registry.fedoraproject.org/fedora:27

test:
	docker run --rm -it -v ${PWD}:/src -w /src $(IMAGE_NAME) ./bootstrap.sh
