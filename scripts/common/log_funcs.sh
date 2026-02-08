#!/usr/bin/env bash
#
# Common logging functions for all scripts
# Source this file to use colored, timestamped logging
#

# ======================================================================================
# ANSI Color Codes
# ======================================================================================
COLOR_RED='\033[0;31m'
COLOR_GREEN='\033[0;32m'
COLOR_YELLOW='\033[0;33m'
COLOR_BLUE='\033[0;34m'
COLOR_RESET='\033[0m'

# ======================================================================================
# Logging Functions
# ======================================================================================

log() {
  printf "${COLOR_BLUE}[%s]${COLOR_RESET} %s\n" "$(date '+%H:%M:%S')" "$*"
}

log_success() {
  printf "${COLOR_GREEN}[%s] ✓ %s${COLOR_RESET}\n" "$(date '+%H:%M:%S')" "$*"
}

log_error() {
  printf "${COLOR_RED}[%s] ✗ %s${COLOR_RESET}\n" "$(date '+%H:%M:%S')" "$*" >&2
}

log_warning() {
  printf "${COLOR_YELLOW}[%s] ⚠ %s${COLOR_RESET}\n" "$(date '+%H:%M:%S')" "$*"
}
