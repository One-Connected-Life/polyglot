# syntax=docker/dockerfile:1
# check=error=true

# This Dockerfile is designed for production, not development. Use with Kamal or build'n'run by hand:
# docker build -t polyglot .
# docker run -d -p 80:80 -e RAILS_MASTER_KEY=<value from config/master.key> --name polyglot polyglot

# For a containerized dev environment, see Dev Containers: https://guides.rubyonrails.org/getting_started_with_devcontainer.html

# Make sure RUBY_VERSION matches the Ruby version in .ruby-version
ARG RUBY_VERSION=3.4.4
FROM docker.io/library/ruby:$RUBY_VERSION-slim AS base

# Rails app lives here
WORKDIR /rails

# Install base packages.
# ffmpeg + libgomp1 are runtime deps for self-hosted audio transcription
# (audio→vocab, issue 3): ffmpeg normalizes uploads to 16kHz WAV, libgomp1 is
# whisper.cpp's OpenMP runtime.
RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y curl libjemalloc2 libvips sqlite3 ffmpeg libgomp1 && \
    ln -s /usr/lib/$(uname -m)-linux-gnu/libjemalloc.so.2 /usr/local/lib/libjemalloc.so && \
    rm -rf /var/lib/apt/lists /var/cache/apt/archives

# Set production environment variables and enable jemalloc for reduced memory usage and latency.
ENV RAILS_ENV="production" \
    BUNDLE_DEPLOYMENT="1" \
    BUNDLE_PATH="/usr/local/bundle" \
    BUNDLE_WITHOUT="development" \
    LD_PRELOAD="/usr/local/lib/libjemalloc.so"

# Throw-away build stage to reduce size of final image
FROM base AS build

# Install packages needed to build gems
RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y build-essential git libvips libyaml-dev pkg-config && \
    rm -rf /var/lib/apt/lists /var/cache/apt/archives

# Install application gems
COPY vendor/* ./vendor/
COPY Gemfile Gemfile.lock ./

RUN bundle install && \
    rm -rf ~/.bundle/ "${BUNDLE_PATH}"/ruby/*/cache "${BUNDLE_PATH}"/ruby/*/bundler/gems/*/.git && \
    # -j 1 disable parallel compilation to avoid a QEMU bug: https://github.com/rails/bootsnap/issues/495
    bundle exec bootsnap precompile -j 1 --gemfile

# Copy application code
COPY . .

# Precompile bootsnap code for faster boot times.
# -j 1 disable parallel compilation to avoid a QEMU bug: https://github.com/rails/bootsnap/issues/495
RUN bundle exec bootsnap precompile -j 1 app/ lib/

# Precompiling assets for production without requiring secret RAILS_MASTER_KEY
RUN SECRET_KEY_BASE_DUMMY=1 ./bin/rails assets:precompile


# ── Whisper build stage: self-hosted transcription for audio→vocab (issue 3) ──
# Compiles whisper.cpp's CLI statically (BUILD_SHARED_LIBS=OFF → one self-contained
# binary, no .so juggling) and bakes a model into the image. "small" is a good
# Dutch/CPU balance; bump WHISPER_MODEL_NAME to ggml-medium.bin for more accuracy.
#
# GGML_NATIVE=OFF avoids -march=native (breaks under the arm64→amd64 QEMU build),
# but on its own it also disables ALL x86 SIMD → scalar fallback, ~5-10x slower
# (a 1.6s clip 504'd in prod). So we explicitly enable the AVX2/FMA/F16C baseline:
# portable across any modern x86-64-v3 CPU (every Hetzner box) AND fast.
FROM base AS whisper
ARG WHISPER_REF=v1.7.4
ARG WHISPER_MODEL_NAME=ggml-small.bin
RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y build-essential cmake git curl && \
    git clone --depth 1 --branch ${WHISPER_REF} https://github.com/ggerganov/whisper.cpp /tmp/whisper && \
    cmake -S /tmp/whisper -B /tmp/whisper/build \
        -DCMAKE_BUILD_TYPE=Release -DBUILD_SHARED_LIBS=OFF \
        -DGGML_NATIVE=OFF -DGGML_AVX=ON -DGGML_AVX2=ON -DGGML_FMA=ON -DGGML_F16C=ON \
        -DWHISPER_BUILD_TESTS=OFF -DWHISPER_BUILD_EXAMPLES=ON && \
    cmake --build /tmp/whisper/build --target whisper-cli -j "$(nproc)" && \
    mkdir -p /opt/whisper/bin /opt/whisper/models && \
    cp /tmp/whisper/build/bin/whisper-cli /opt/whisper/bin/whisper-cli && \
    curl -fL -o /opt/whisper/models/${WHISPER_MODEL_NAME} \
        https://huggingface.co/ggerganov/whisper.cpp/resolve/main/${WHISPER_MODEL_NAME} && \
    rm -rf /tmp/whisper /var/lib/apt/lists /var/cache/apt/archives


# Final stage for app image
FROM base

# Run and own only the runtime files as a non-root user for security
RUN groupadd --system --gid 1000 rails && \
    useradd rails --uid 1000 --gid 1000 --create-home --shell /bin/bash
USER 1000:1000

# Copy built artifacts: gems, application
COPY --chown=rails:rails --from=build "${BUNDLE_PATH}" "${BUNDLE_PATH}"
COPY --chown=rails:rails --from=build /rails /rails

# Self-hosted transcription binary + model (audio→vocab, issue 3). Transcriber
# reads these paths via WHISPER_CLI / WHISPER_MODEL; ffmpeg is on PATH from base.
COPY --chown=rails:rails --from=whisper /opt/whisper /opt/whisper
ENV WHISPER_CLI=/opt/whisper/bin/whisper-cli \
    WHISPER_MODEL=/opt/whisper/models/ggml-small.bin

# Entrypoint prepares the database.
ENTRYPOINT ["/rails/bin/docker-entrypoint"]

# Start server via Thruster by default, this can be overwritten at runtime
EXPOSE 80
CMD ["./bin/thrust", "./bin/rails", "server"]
