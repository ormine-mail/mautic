#!/bin/bash

# Default verbosity
VERBOSE=false

# Check for verbose flag
for arg in "$@"; do
  if [ "$arg" = "-v" ]; then
    VERBOSE=true
  fi
done

# Function to echo with icons
function echo_step() {
  echo -e "\n🚀 $1"
}

function echo_success() {
  echo -e "✅ $1"
}

function echo_info() {
  echo -e "ℹ️  $1"
}

# Function to run command with conditional output
function run_command() {
  if [ "$VERBOSE" = true ]; then
    echo_info "Running: $1"
    eval "$1"
  else
    echo_info "Running: $1"
    eval "$1 > /dev/null 2>&1"
    if [ $? -eq 0 ]; then
      echo_success "Command completed successfully"
    else
      echo -e "❌ Command failed"
      echo -e "   Run with -v flag to see detailed output"
      exit 1
    fi
  fi
}

# Build web image
echo_step "Building Mautic web image..."
run_command "docker build --build-arg CONTAINER_ROLE=web --target web --no-cache . -t registry.base.ormine.nl/galvani/mautic-web:latest"

# Build worker image
echo_step "Building Mautic worker image..."
run_command "docker build --build-arg CONTAINER_ROLE=web --target worker . -t registry.base.ormine.nl/galvani/mautic-worker:latest"

# Push web image
echo_step "Pushing Mautic web image to registry..."
run_command "docker push registry.base.ormine.nl/galvani/mautic-web:latest"

# Push worker image
echo_step "Pushing Mautic worker image to registry..."
run_command "docker push registry.base.ormine.nl/galvani/mautic-worker:latest"

echo_success "All operations completed successfully!"