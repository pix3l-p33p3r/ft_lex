FROM debian:bullseye-slim

# Install basic tools
RUN apt-get update && apt-get install -y \
    curl \
    xz-utils \
    git \
    make \
    gcc \
    flex \
    && rm -rf /var/lib/apt/lists/*

# Install Zig
RUN curl -sSf https://ziglang.org/download/0.11.0/zig-linux-x86_64-0.11.0.tar.xz | tar -xJ -C /usr/local \
    && ln -s /usr/local/zig-linux-x86_64-0.11.0/zig /usr/local/bin/zig

# Set working directory
WORKDIR /app

# Copy project files
COPY . .

# Build the project
CMD ["make"]
