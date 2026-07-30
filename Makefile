# umbrelOS Pipa image builder
#
# Usage:
#   make builder   Build the Docker builder image
#   make image     Build the umbrelOS pipa flash archive
#   make clean     Remove generated images

SHELL := /bin/bash
BUILDER_IMAGE := umbrel-pipa-builder
OUTPUT_DIR := output

BUILD_GIT_REV ?= $(shell git rev-parse --short HEAD 2>/dev/null || echo unknown)
UMBREL_REF ?= 1.7.4
PIPA_PKGS_URL ?= https://thespider2.github.io/pipa-pkgs/repo/ubuntu/

DOCKER_RUN := docker run --rm --privileged \
	-v "$(CURDIR)/$(OUTPUT_DIR):/build/output" \
	-v "$(CURDIR)/work:/build/work" \
	-v /var/run/docker.sock:/var/run/docker.sock \
	-v /dev:/dev \
	-e BUILD_GIT_REV="$(BUILD_GIT_REV)" \
	-e UMBREL_REF="$(UMBREL_REF)" \
	-e PIPA_PKGS_URL="$(PIPA_PKGS_URL)" \
	$(BUILDER_IMAGE)

.PHONY: help builder image clean check-docker

help:
	@echo "umbrelOS Pipa image builder"
	@echo
	@echo "Targets:"
	@echo "  builder   Build the Docker builder image"
	@echo "  image     Build the umbrelOS pipa flash archive"
	@echo "  clean     Remove generated images"
	@echo
	@echo "Environment variables:"
	@echo "  UMBREL_REF       Upstream umbrel git tag/commit (default: 1.7.4)"
	@echo "  PIPA_PKGS_URL    apt repo URL for pipa packages"
	@echo "  BUILD_GIT_REV    Git revision stamped into build metadata"

check-docker:
	@command -v docker >/dev/null || { echo "docker is required but not installed."; exit 1; }

builder: check-docker
	docker build -t $(BUILDER_IMAGE) .

$(OUTPUT_DIR):
	mkdir -p $(OUTPUT_DIR)

image: builder $(OUTPUT_DIR)
	$(DOCKER_RUN)

clean:
	rm -rf $(OUTPUT_DIR)/*
