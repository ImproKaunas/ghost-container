ARG GHOST_VERSION=5.130.0
ARG GIT_REPO=https://github.com/ImproKaunas/ghost-source.git
ARG GIT_BRANCH=improkaunas.lt/main

FROM node:20-bookworm-slim as ghost-builder
ARG GIT_REPO
ARG GIT_BRANCH
ARG GHOST_VERSION

RUN <<END
	set -eu
	apt-get update -qq
	apt-get upgrade -y
	apt-get install -y \
		git \
		gosu \
	>/dev/null
	rm --recursive --force \
		"/var/lib/apt/lists/*"
END

RUN <<END
	set -eu
	say() { echo "\033[1;34m$1\033[0m"; }

	say "Cloning git repository ($GIT_BRANCH at $GIT_REPO).."
	gosu node git clone \
		--depth 1 \
		--recurse-submodules \
		--shallow-submodules \
		--branch "$GIT_BRANCH" \
		"$GIT_REPO" /tmp/ghost-build

	cd /tmp/ghost-build

	say "Installing dependencies.."
	gosu node yarn install \
		--frozen-lockfile \
		--non-interactive

	say "Building Ghost.."
	gosu node yarn build

	say "Creating the Ghost release file.."
	gosu node yarn archive

	mkdir -p "/usr/src/ghost/$GHOST_VERSION"
	
	say "Saving files to /usr/src/ghost/$GHOST_VERSION"

	cp --verbose\
		yarn.lock \
		"/usr/src/ghost/$GHOST_VERSION/yarn.lock"

	cp --verbose\
		"ghost/core/ghost-${GHOST_VERSION}.tgz" \
		"/usr/src/ghost/$GHOST_VERSION/release.tgz"

	for path in apps/*; do
		if [ -d "$path" ]; then
			app=$(basename "$path")
			for output in umd; do
				if [ -d "$path/$output" ]; then
					mkdir -p "/usr/src/ghost/$GHOST_VERSION/apps/$app/$output"
					cp --recursive --verbose \
						"$path/$output" \
						"/usr/src/ghost/$GHOST_VERSION/apps/$app"
				fi
			done
		fi
	done

	cd ..

	say "Cleaning up.."
	rm --recursive --force \
		"/tmp/yarn*" \
		"/tmp/v8*" \
		"/tmp/ghost-build"
END

LABEL org.opencontainers.image.version="$GIT_BRANCH:$GHOST_VERSION-builder"


FROM docker.io/ghost:${GHOST_VERSION}

COPY --from=ghost-builder \
	"/usr/src/ghost/$GHOST_VERSION" \
	"/usr/src/ghost/$GHOST_VERSION"

WORKDIR /

RUN <<END
	set -eu
	say() { echo "\033[1;34m$1\033[0m"; }

	say "Removing existing Ghost installation.."
	rm --recursive --force "$GHOST_INSTALL"

	say "Creating Ghost installation directory.."
	install \
		--directory "$GHOST_INSTALL" \
		--owner node \
		--group node \
		--mode 0755 \
		--verbose

	say "Installing yarn.lock.."
	gosu node install --verbose -D \
		"/usr/src/ghost/$GHOST_VERSION/yarn.lock" \
		"$GHOST_INSTALL/versions/$GHOST_VERSION/yarn.lock"

	say "Installing Ghost from archive.."
	gosu node ghost install \
		--archive "/usr/src/ghost/$GHOST_VERSION/release.tgz" \
		--dir "$GHOST_INSTALL" \
		--no-prompt \
		--no-stack \
		--no-setup \
		--no-check-empty

	say "Copying apps to public directory.."
	install -d "$GHOST_INSTALL/versions/$GHOST_VERSION/core/frontend/public/apps"
	for path in "/usr/src/ghost/$GHOST_VERSION/apps/"*; do
		if [ -d "$path" ]; then
			app=$(basename "$path")
			echo "$app"
			cp --recursive --verbose \
				"/usr/src/ghost/$GHOST_VERSION/apps/$app" \
				"$GHOST_INSTALL/versions/$GHOST_VERSION/core/frontend/public/apps/$app"
		fi
	done

	say "Setting up content directory.."

	mv --verbose \
		"$GHOST_CONTENT" \
		"$GHOST_INSTALL/content.orig"

	install \
		--directory "$GHOST_CONTENT" \
		--owner node \
		--group node \
		--mode 0755 \
		--verbose

	say "Cleaning up.."
	rm --recursive --force \
		"/tmp/yarn*" \
		"/tmp/v8*"
END

WORKDIR "$GHOST_INSTALL"

ARG GIT_BRANCH
ARG GHOST_VERSION
LABEL org.opencontainers.image.version="$GIT_BRANCH:$GHOST_VERSION"
