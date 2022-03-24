FROM ubuntu:focal
RUN apt-get -y update && apt-get --no-install-recommends -y install \
    expect=5.45.4-2build1 \
    php-cli=2:7.4+75 \
    wget=1.20.3-1ubuntu2 \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

