#!/bin/sh

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo "${YELLOW}Starting ft_lex development environment...${NC}"

# Check if Docker is running
if ! docker info > /dev/null 2>&1; then
    echo "Error: Docker is not running"
    exit 1
fi

# Build and start the development container
if [ "$1" = "build" ]; then
    echo "${GREEN}Building Docker image...${NC}"
    docker-compose build
elif [ "$1" = "test" ]; then
    echo "${GREEN}Running tests...${NC}"
    docker-compose run --rm ft_lex make test
elif [ "$1" = "clean" ]; then
    echo "${GREEN}Cleaning build artifacts...${NC}"
    docker-compose run --rm ft_lex make clean
else
    echo "${GREEN}Starting development shell...${NC}"
    docker-compose run --rm ft_lex
fi
