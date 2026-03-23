#!/usr/bin/env bash
set -Eeuo pipefail

APP_NAME="NameSome"
APP_DIR="/opt/${APP_NAME}"
LOG_DIR="${APP_DIR}/install-logs"
TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
LOG_FILE="${LOG_DIR}/installation-${TIMESTAMP}.log"
TOTAL_STEPS=7
CURRENT_STEP=0

GITHUB_USER="RaziRizwan0"
GITHUB_REPO="name-app"
GITHUB_BRANCH="master"
BASE_URL="https://raw.githubusercontent.com/${GITHUB_USER}/${GITHUB_REPO}/${GITHUB_BRANCH}"
COMPOSE_URL="${BASE_URL}/docker-compose.yml"
ENV_URL="${BASE_URL}/backend/.env"

BOLD='\033[1m'
DIM='\033[2m'
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[1;34m'
CYAN='\033[0;36m'
NC='\033[0m'

print_line() {
  echo -e "${BOLD}============================================================${NC}"
}

print_banner() {
  echo
  echo -e "${BOLD}==========================================${NC}"
  echo -e "${BOLD}   ${APP_NAME} Installation - ${TIMESTAMP}${NC}"
  echo -e "${BOLD}==========================================${NC}"
  echo
  echo "Welcome to ${APP_NAME} Installer!"
  echo "This script will install everything for you."
  echo -e "${DIM}Source: https://github.com/${GITHUB_USER}/${GITHUB_REPO}${NC}"
  echo
}

step() {
  CURRENT_STEP=$((CURRENT_STEP + 1))
  echo
  print_line
  echo -e "${BOLD}[$(date '+%Y-%m-%d %H:%M:%S')] Step ${CURRENT_STEP}/${TOTAL_STEPS}: $1${NC}"
  print_line
}

info() {
  echo -e "${BLUE} - $*${NC}"
}

success() {
  echo -e "${GREEN} - $*${NC}"
}

warn() {
  echo -e "${YELLOW} - $*${NC}"
}

fail() {
  echo -e "${RED} - $*${NC}" >&2
  echo
  echo "Check the log file for details: ${LOG_FILE}" >&2
  exit 1
}

substep() {
  echo "   $*"
}

done_msg() {
  echo -e "     ${GREEN}Done.${NC}"
}

command_exists() {
  command -v "$1" >/dev/null 2>&1
}

run_cmd() {
  local message="$1"
  shift
  info "${message}..."
  if "$@" >>"${LOG_FILE}" 2>&1; then
    success "${message} completed"
  else
    fail "${message} failed"
  fi
}

detect_os() {
  if [[ -f /etc/os-release ]]; then
    . /etc/os-release
    OS_NAME="${NAME:-Unknown}"
    OS_VERSION="${VERSION_ID:-Unknown}"
  else
    OS_NAME="Unknown"
    OS_VERSION="Unknown"
  fi
}

get_primary_ip() {
  hostname -I 2>/dev/null | awk '{print $1}'
}

wait_for_app() {
  local url="$1"
  local retries=30
  local delay=3
  local i

  for ((i=1; i<=retries; i++)); do
    if curl -fsS "${url}" >>"${LOG_FILE}" 2>&1; then
      return 0
    fi
    echo -ne "\r - Waiting for application to be ready... (${i}/${retries})"
    sleep "${delay}"
  done
  echo
  return 1
}

trap 'fail "Installation failed at line ${LINENO}"' ERR

mkdir -p "${LOG_DIR}"
touch "${LOG_FILE}"

print_banner

step "Checking system requirements"
detect_os
info "Operating System: ${OS_NAME} ${OS_VERSION}"

if [[ "${EUID}" -ne 0 ]]; then
  fail "Please run this installer as root or with sudo"
fi

if ! command_exists curl; then
  fail "curl is required but not installed"
fi

if ! command_exists docker; then
  fail "Docker is required but not installed"
fi

if ! docker compose version >>"${LOG_FILE}" 2>&1; then
  fail "Docker Compose plugin is required but not available"
fi

success "System requirements check passed"

step "Preparing installation directory"
run_cmd "Creating application directory" mkdir -p "${APP_DIR}"
run_cmd "Creating log directory" mkdir -p "${LOG_DIR}"

step "Downloading configuration files"
run_cmd "Downloading docker-compose.yml" curl -fsSL "${COMPOSE_URL}" -o "${APP_DIR}/docker-compose.yml"
run_cmd "Downloading .env.example" curl -fsSL "${ENV_URL}" -o "${APP_DIR}/.env.example"
done_msg

step "Setting up environment file"
if [[ -f "${APP_DIR}/.env" ]]; then
  BACKUP_FILE="${APP_DIR}/.env.backup-${TIMESTAMP}"
  info "Existing .env file found"
  run_cmd "Creating backup of existing .env" cp "${APP_DIR}/.env" "${BACKUP_FILE}"
  warn "Keeping existing .env file"
else
  run_cmd "Creating .env from template" cp "${APP_DIR}/.env.example" "${APP_DIR}/.env"
fi
done_msg

step "Pulling Docker images"
substep "This may take a few minutes depending on your connection."
run_cmd "Pulling container images" docker compose --env-file "${APP_DIR}/.env" -f "${APP_DIR}/docker-compose.yml" pull

step "Starting application"
run_cmd "Starting containers" docker compose --env-file "${APP_DIR}/.env" -f "${APP_DIR}/docker-compose.yml" up -d

step "Verifying application health"
APP_IP="$(get_primary_ip)"
APP_URL="http://${APP_IP}:80"

info "Checking application availability"
if wait_for_app "${APP_URL}"; then
  echo
  success "Application is responding"
else
  echo
  warn "Application containers started, but HTTP check did not succeed yet"
  warn "Please review container logs with:"
  echo "   docker compose --env-file ${APP_DIR}/.env -f ${APP_DIR}/docker-compose.yml logs"
fi

step "Installation complete"
echo
echo -e "${GREEN}${BOLD}Your instance is ready to use!${NC}"
echo
echo "You can access ${APP_NAME} at:"
echo -e "${CYAN}${APP_URL}${NC}"
echo
echo "Files installed to:"
echo "  ${APP_DIR}"
echo
echo "Log file:"
echo "  ${LOG_FILE}"
echo
echo -e "${YELLOW}WARNING:${NC} Back up your ${BOLD}${APP_DIR}/.env${NC} file to a safe location."
echo
success "${APP_NAME} installation completed successfully"
