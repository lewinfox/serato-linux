IMAGE := serato-wine

.PHONY: container install links

## Build the Docker image (wine-staging + patched dwrite)
container:
	docker build -t $(IMAGE) .

## Interactive setup: image, host config, Serato, link handler, launcher
install:
	./install.sh

## Register seratodjpro:// and seratodjlite:// links on the host (sign-in)
links:
	./link-handlers.sh
