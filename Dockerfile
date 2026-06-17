# syntax=docker/dockerfile:1
ARG LANGUAGETOOL_VERSION=6.8
ARG TARGETARCH
# Définition de la variable pour la locale (fr_FR.UTF-8 par défaut)
ARG DEFAULT_LANG=fr_FR.UTF-8

FROM debian:bookworm AS build

ENV DEBIAN_FRONTEND=noninteractive

# Récupération de l'argument de locale pour l'environnement de build
ARG DEFAULT_LANG
ENV LANG=${DEFAULT_LANG}

# Install common packages
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    apt-get update -y && \
    apt-get install -y --no-install-recommends \
        locales \
        bash \
        libgomp1 \
        openjdk-17-jdk-headless \
        git \
        maven \
        unzip \
        xmlstarlet

# Install ARM64-specific packages (Correction de la syntaxe de la monture cache)
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    if [ "$TARGETARCH" = "arm64" ]; then \
        apt-get install -y --no-install-recommends \
            build-essential \
            cmake \
            mercurial \
            texlive \
            wget \
            zip; \
    fi

# Génération dynamique de la locale choisie
RUN sed -i -e "s/# ${LANG} ${LANG##*.}/${LANG} ${LANG##*.}/" /etc/locale.gen && \
    dpkg-reconfigure --frontend=noninteractive locales && \
    update-locale LANG=${LANG}

ARG LANGUAGETOOL_VERSION
RUN git clone https://github.com/languagetool-org/languagetool.git --depth 1 -b v${LANGUAGETOOL_VERSION}
WORKDIR /languagetool

# Pre-download Maven dependencies using cache
RUN --mount=type=cache,target=/root/.m2 mvn dependency:go-offline -DskipTests

# Build LanguageTool standalone
RUN --mount=type=cache,target=/root/.m2 mvn --projects languagetool-standalone --also-make package -DskipTests --quiet

RUN LANGUAGETOOL_DIST_VERSION=$(xmlstarlet sel -N "x=http://maven.apache.org/POM/4.0.0" -t -v "//x:project/x:properties/x:revision" pom.xml) && unzip /languagetool/languagetool-standalone/target/LanguageTool-${LANGUAGETOOL_DIST_VERSION}.zip -d /dist
RUN LANGUAGETOOL_DIST_FOLDER=$(find /dist/ -name 'LanguageTool-*') && mv $LANGUAGETOOL_DIST_FOLDER /dist/LanguageTool

# Execute workarounds for ARM64 architectures.
# https://github.com/languagetool-org/languagetool/issues/4543
WORKDIR /
COPY --link --chmod=755 arm64-workaround/bridj.sh arm64-workaround/bridj.sh
RUN if [ "$TARGETARCH" = "arm64" ]; then \
        echo "Applying ARM64 workaround for BridJ..." && \
        bash arm64-workaround/bridj.sh; \
    else \
        echo "Skipping ARM64 workarounds for $TARGETARCH"; \
    fi

WORKDIR /languagetool

FROM alpine:3.24.0

ARG TARGETARCH
# Récupération de la locale pour le stage final (Alpine)
ARG DEFAULT_LANG
ENV LANG=${DEFAULT_LANG}

RUN apk add --no-cache \
    bash \
    curl \
    fasttext \
    libc6-compat \
    libstdc++ \
    openjdk17-jre-headless

RUN if [ "$TARGETARCH" = "arm64" ]; then \
        apk add --no-cache hunspell zip; \
    fi

RUN addgroup -S languagetool && adduser -S languagetool -G languagetool

COPY --chown=languagetool:languagetool --from=build /dist/LanguageTool /LanguageTool

RUN if [ "$TARGETARCH" = "arm64" ]; then \
        echo "Applying ARM64 workaround for Hunspell..."; \
        HUNSPELL_SRC=$(find /usr/lib -name 'libhunspell-*.so*' -type f | head -n 1); \
        if [ -z "$HUNSPELL_SRC" ]; then \
            echo "Unable to locate hunspell shared library in /usr/lib"; \
            exit 1; \
        fi; \
        mkdir -p /tmp/hunspell/linux-aarch64; \
        cp "$HUNSPELL_SRC" /tmp/hunspell/linux-aarch64/libhunspell.so; \
        (cd /tmp/hunspell && zip /LanguageTool/libs/hunspell.jar linux-aarch64/libhunspell.so); \
        rm -rf /tmp/hunspell; \
    fi

WORKDIR /LanguageTool

RUN mkdir /nonexistent && touch /nonexistent/.languagetool.cfg

COPY --chown=languagetool:languagetool start.sh config.properties ./

RUN install -d -m 755 /fastText \
    && curl -L https://dl.fbaipublicfiles.com/fasttext/supervised-models/lid.176.bin -o /fastText/lid.176.bin \
    && chown -R languagetool:languagetool /fastText

RUN set -eux; \
    echo "fasttextModel=/fastText/lid.176.bin" >> config.properties; \
    echo "fasttextBinary=$(command -v fasttext)" >> config.properties; \
    chown languagetool:languagetool config.properties

RUN install -d -m 755 /dict && chown languagetool:languagetool /dict

COPY --chown=languagetool:languagetool docker-entrypoint.sh docker-entrypoint.sh
RUN chmod +x docker-entrypoint.sh

USER languagetool

HEALTHCHECK --timeout=10s --start-period=5s CMD curl --fail --data "language=en-US&text=a simple test" http://localhost:8010/v2/check || exit 1

ENTRYPOINT ["/bin/bash", "docker-entrypoint.sh"]
CMD ["/bin/bash", "start.sh"]

EXPOSE 8010
