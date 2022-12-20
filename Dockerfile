FROM ghcr.io/getzola/zola:v0.16.1 AS base
WORKDIR /usr/local/app/
COPY ./ ./
