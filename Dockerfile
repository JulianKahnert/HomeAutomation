# ================================
# Build image
# ================================
FROM swift:6.4-noble AS build

# Install OS updates
RUN export DEBIAN_FRONTEND=noninteractive DEBCONF_NONINTERACTIVE_SEEN=true \
    && apt-get -q update \
    && apt-get -q dist-upgrade -y \
    && apt-get install -y libjemalloc-dev

# Set up a build area
WORKDIR /build

# First just resolve dependencies.
# This creates a cached layer that can be reused
# as long as your Package.swift/Package.resolved
# files do not change.
COPY ./Package.* ./
RUN swift package resolve

# Copy entire repo into container
COPY . .

# Capture git commit hash for runtime logging
RUN git rev-parse --short HEAD > /tmp/git-commit 2>/dev/null || echo "unknown" > /tmp/git-commit

# Build the application, with optimizations, with static linking, and using jemalloc
# N.B.: The static version of jemalloc is incompatible with the static Swift runtime.
RUN swift build -c release \
        --product Server \
        --static-swift-stdlib \
        -Xlinker -ljemalloc

# Switch to the staging area
WORKDIR /staging

# Copy main executable to staging area
RUN cp "$(swift build --package-path /build -c release --show-bin-path)/Server" ./

# Copy static swift backtracer binary to staging area
RUN cp "/usr/libexec/swift/linux/swift-backtrace-static" ./

# Copy resources bundled by SPM to staging area.
# The native build system names them `<Package>_<Target>.resources`, swiftbuild
# (the default since Swift 6.4) names them `<Package>_<Target>.bundle`; the
# generated accessor only looks for the name its build system wrote, so copy both.
# Every module with resources gets a generated resource_bundle_accessor.swift
# whose fatalError names its bundle: fail the build when one of them is not staged,
# instead of shipping an image that crashes on the first `Bundle.module` access.
RUN set -eu; \
    bin_path="$(swift build --package-path /build -c release --show-bin-path)"; \
    find -L "$bin_path/" -maxdepth 1 -type d \( -name '*.resources' -o -name '*.bundle' \) -exec cp -Ra {} ./ \; ; \
    expected="$(find /build/.build \( -path /build/.build/checkouts -o -path /build/.build/repositories \) -prune -o -name resource_bundle_accessor.swift -exec sed -n 's/.*unable to find bundle named \([A-Za-z0-9_.-]*\).*/\1/p' {} + | sort -u)"; \
    [ -n "$expected" ] || { echo "error: no resource_bundle_accessor.swift found, cannot check resource bundles" >&2; exit 1; }; \
    for name in $expected; do \
      if [ -d "./$name.bundle" ] || [ -d "./$name.resources" ]; then \
        echo "staged resource bundle: $name"; \
      else \
        echo "error: resource bundle $name is missing from /staging (searched $bin_path)" >&2; exit 1; \
      fi; \
    done

# Copy any resources from the public directory and views directory if the directories exist
# Ensure that by default, neither the directory nor any of its contents are writable.
RUN [ -d /build/Public ] && { mv /build/Public ./Public && chmod -R a-w ./Public; } || true
RUN [ -d /build/Resources ] && { mv /build/Resources ./Resources && chmod -R a-w ./Resources; } || true

# ================================
# Run image
# ================================
FROM ubuntu:resolute

# Make sure all system packages are up to date, and install only essential packages.
RUN export DEBIAN_FRONTEND=noninteractive DEBCONF_NONINTERACTIVE_SEEN=true \
    && apt-get -q update \
    && apt-get -q dist-upgrade -y \
    && apt-get -q install -y \
      libjemalloc2 \
      ca-certificates \
      curl \
      tzdata \
# If your app or its dependencies import FoundationNetworking, also install `libcurl4`.
      libcurl4 \
# If your app or its dependencies import FoundationXML, also install `libxml2`.
      # libxml2 \
    && rm -r /var/lib/apt/lists/*

# Create a vapor user and group with /app as its home directory
RUN useradd --user-group --create-home --system --skel /dev/null --home-dir /app vapor

# Switch to the new home directory
WORKDIR /app

# Copy built executable and any staged resources from builder
COPY --from=build --chown=vapor:vapor /staging /app

# Copy git commit hash for startup logging
COPY --from=build --chown=vapor:vapor /tmp/git-commit /app/git-commit

# Provide configuration needed by the built-in crash reporter and some sensible default behaviors.
ENV SWIFT_BACKTRACE=enable=yes,sanitize=yes,threads=all,images=all,interactive=no,swift-backtrace=./swift-backtrace-static

# Ensure all further commands run as the vapor user
USER vapor:vapor

# Let Docker bind to port 8080
EXPOSE 8080

# Start the Vapor service when the image is run, default to listening on 8080 in production environment
ENTRYPOINT ["./Server"]
CMD ["serve", "--env", "production", "--hostname", "0.0.0.0", "--port", "8080"]
