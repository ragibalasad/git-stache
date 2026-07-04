#!/usr/bin/env bash
#
# github-sync.sh
#
# Pulls your stored GitHub PAT from git's credential helper, discovers your
# authenticated username, lists ALL your repos (public + private), and
# clones any that are missing locally or pulls the ones you already have.
#
# Requires: git, curl, jq  (no `gh` CLI used anywhere)

set -uo pipefail

# ------------------------------------------------------------------------
# Config — change these to taste
# ------------------------------------------------------------------------
PER_PAGE=100
GITHUB_API="https://api.github.com"
GITHUB_HOST="github.com"

# XDG Base Directory spec: config belongs under $XDG_CONFIG_HOME (default ~/.config)
CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/github-sync"
CONFIG_FILE="$CONFIG_DIR/config"

# ------------------------------------------------------------------------
# Logging helpers
# ------------------------------------------------------------------------
COLOR_RESET="\033[0m"
COLOR_BLUE="\033[1;34m"
COLOR_GREEN="\033[1;32m"
COLOR_YELLOW="\033[1;33m"
COLOR_RED="\033[1;31m"
COLOR_GRAY="\033[0;90m"

ts() { date "+%H:%M:%S"; }

log()      { echo -e "${COLOR_GRAY}[$(ts)]${COLOR_RESET} $*"; }
info()     { echo -e "${COLOR_GRAY}[$(ts)]${COLOR_RESET} ${COLOR_BLUE}==>${COLOR_RESET} $*"; }
success()  { echo -e "${COLOR_GRAY}[$(ts)]${COLOR_RESET} ${COLOR_GREEN}✔${COLOR_RESET} $*"; }
warn()     { echo -e "${COLOR_GRAY}[$(ts)]${COLOR_RESET} ${COLOR_YELLOW}!${COLOR_RESET} $*"; }
err()      { echo -e "${COLOR_GRAY}[$(ts)]${COLOR_RESET} ${COLOR_RED}✘${COLOR_RESET} $*" >&2; }
section()  { echo -e "\n${COLOR_BLUE}== $* ==${COLOR_RESET}"; }

# ------------------------------------------------------------------------
# Base directory resolution — first run asks where to store repos,
# then remembers the choice in $CONFIG_FILE for every run after that.
# ------------------------------------------------------------------------
resolve_base_dir() {
  # An explicit env var override always wins, config file or not.
  if [[ -n "${GH_SYNC_BASE_DIR:-}" ]]; then
    BASE_DIR="$GH_SYNC_BASE_DIR"
    return
  fi

  if [[ -f "$CONFIG_FILE" ]]; then
    # shellcheck source=/dev/null
    source "$CONFIG_FILE"
    if [[ -n "${BASE_DIR:-}" ]]; then
      return
    fi
    warn "Config file at $CONFIG_FILE exists but has no BASE_DIR set — re-running setup."
  fi

  section "First-time setup: choose where repos should be stored"
  echo "  0. Default   (\$HOME/gitstache)"
  echo "  1. Desktop   (\$HOME/Desktop/gitstache)"
  echo "  2. Documents (\$HOME/Documents/gitstache)"
  echo "  3. Downloads (\$HOME/Downloads/gitstache)"
  echo "  4. Enter a custom location"
  echo ""

  local choice
  read -r -p "Select an option [0-4]: " choice

  case "$choice" in
    1) BASE_DIR="$HOME/Desktop/gitstache" ;;
    2) BASE_DIR="$HOME/Documents/gitstache" ;;
    3) BASE_DIR="$HOME/Downloads/gitstache" ;;
    4)
      read -r -e -p "Enter custom path: " custom_path
      # Expand a leading ~ manually since read doesn't do it for us
      BASE_DIR="${custom_path/#\~/$HOME}"
      ;;
    0|"") BASE_DIR="$HOME/gitstache" ;;
    *)
      warn "Unrecognized option '$choice' — falling back to default."
      BASE_DIR="$HOME/gitstache"
      ;;
  esac

  mkdir -p "$CONFIG_DIR"
  {
    echo "# github-sync config — generated $(date '+%Y-%m-%d %H:%M:%S')"
    echo "# Delete this file (or edit BASE_DIR below) to change the storage location."
    echo "BASE_DIR=\"$BASE_DIR\""
  } > "$CONFIG_FILE"

  success "Saved location choice to $CONFIG_FILE"
}

resolve_base_dir

# ------------------------------------------------------------------------
# Sanity checks
# ------------------------------------------------------------------------
for bin in git curl jq; do
  if ! command -v "$bin" >/dev/null 2>&1; then
    err "Required command '$bin' not found in PATH. Please install it."
    exit 1
  fi
done

# ------------------------------------------------------------------------
# Step 1: Pull the stored PAT out of git's credential helper
# ------------------------------------------------------------------------
section "Step 1/4: Retrieving stored credentials"

CRED_OUTPUT=$(printf 'protocol=https\nhost=%s\n\n' "$GITHUB_HOST" | git credential fill 2>/dev/null)

GH_USERNAME_HINT=$(echo "$CRED_OUTPUT" | sed -n 's/^username=//p')
GH_TOKEN=$(echo "$CRED_OUTPUT" | sed -n 's/^password=//p')

if [[ -z "${GH_TOKEN:-}" ]]; then
  err "Could not retrieve a stored PAT for host '$GITHUB_HOST'."
  err "Make sure a credential helper is configured (git config --get credential.helper)"
  err "and that you've authenticated at least once (e.g. a manual git push)."
  exit 1
fi

success "Retrieved a token from the credential store (hint username: ${GH_USERNAME_HINT:-none})"

# ------------------------------------------------------------------------
# Step 2: Confirm identity via the API (token is the real source of truth)
# ------------------------------------------------------------------------
section "Step 2/4: Verifying identity with GitHub API"

USER_RESPONSE=$(curl -s -H "Authorization: token $GH_TOKEN" \
                       -H "Accept: application/vnd.github+json" \
                       "$GITHUB_API/user")

GH_USERNAME=$(echo "$USER_RESPONSE" | jq -r '.login // empty')

if [[ -z "$GH_USERNAME" ]]; then
  err "Failed to authenticate with the retrieved token."
  ERR_MSG=$(echo "$USER_RESPONSE" | jq -r '.message // "unknown error"')
  err "GitHub API said: $ERR_MSG"
  exit 1
fi

success "Authenticated as: $GH_USERNAME"

# ------------------------------------------------------------------------
# Step 3: List ALL repos (public + private) via pagination
# ------------------------------------------------------------------------
section "Step 3/4: Fetching repository list"

mkdir -p "$BASE_DIR"

REPOS_JSON="[]"
page=1
while :; do
  info "Fetching page $page (per_page=$PER_PAGE)..."
  RESPONSE=$(curl -s -H "Authorization: token $GH_TOKEN" \
                    -H "Accept: application/vnd.github+json" \
                    "$GITHUB_API/user/repos?per_page=$PER_PAGE&page=$page&affiliation=owner&sort=full_name")

  # Bail out cleanly on API errors (rate limit, bad token, etc.)
  if echo "$RESPONSE" | jq -e 'type == "object" and has("message")' >/dev/null 2>&1; then
    ERR_MSG=$(echo "$RESPONSE" | jq -r '.message')
    err "GitHub API error on page $page: $ERR_MSG"
    exit 1
  fi

  COUNT=$(echo "$RESPONSE" | jq 'length')
  if [[ "$COUNT" -eq 0 ]]; then
    break
  fi

  REPOS_JSON=$(jq -s '.[0] + .[1]' <(echo "$REPOS_JSON") <(echo "$RESPONSE"))
  page=$((page + 1))
done

TOTAL=$(echo "$REPOS_JSON" | jq 'length')
PRIVATE_COUNT=$(echo "$REPOS_JSON" | jq '[.[] | select(.private == true)] | length')
PUBLIC_COUNT=$((TOTAL - PRIVATE_COUNT))

success "Found $TOTAL repos ($PUBLIC_COUNT public, $PRIVATE_COUNT private)"

# ------------------------------------------------------------------------
# Step 4: Sync each repo — clone if missing, pull if present
# ------------------------------------------------------------------------
section "Step 4/4: Syncing repositories into $BASE_DIR"

SYNCED=0
CLONED=0
FAILED=0
SKIPPED=0

# Read repos as tab-separated: name, clone_url, private, default_branch
while IFS=$'\t' read -r name clone_url is_private default_branch; do
  target_dir="$BASE_DIR/$name"
  vis_label="public"
  [[ "$is_private" == "true" ]] && vis_label="private"

  echo ""
  info "Repo: ${COLOR_YELLOW}$name${COLOR_RESET} [$vis_label] (default branch: $default_branch)"

  if [[ -d "$target_dir/.git" ]]; then
    log "Local copy exists at $target_dir — pulling latest changes..."
    echo -e "    ${COLOR_GRAY}\$ git -C \"$target_dir\" pull --ff-only --progress${COLOR_RESET}"
    ( cd "$target_dir" && git pull --ff-only --progress )
    result=$?
    if [[ $result -eq 0 ]]; then
      success "Pulled: $name"
      SYNCED=$((SYNCED + 1))
    else
      err "Pull failed for: $name (check for local changes / diverged branch)"
      FAILED=$((FAILED + 1))
    fi
  elif [[ -d "$target_dir" ]]; then
    warn "Directory $target_dir exists but is not a git repo — skipping to avoid clobbering it."
    SKIPPED=$((SKIPPED + 1))
  else
    log "No local copy found — cloning fresh into $target_dir..."
    echo -e "    ${COLOR_GRAY}\$ git clone --progress \"$clone_url\" \"$target_dir\"${COLOR_RESET}"
    git clone --progress "$clone_url" "$target_dir"
    result=$?
    if [[ $result -eq 0 ]]; then
      success "Cloned: $name"
      CLONED=$((CLONED + 1))
    else
      err "Clone failed for: $name"
      FAILED=$((FAILED + 1))
    fi
  fi
done < <(echo "$REPOS_JSON" | jq -r '.[] | [.name, .clone_url, .private, .default_branch] | @tsv')

# ------------------------------------------------------------------------
# Summary
# ------------------------------------------------------------------------
section "Summary"
echo -e "  Authenticated user : ${COLOR_YELLOW}$GH_USERNAME${COLOR_RESET}"
echo -e "  Total repos found  : $TOTAL ($PUBLIC_COUNT public, $PRIVATE_COUNT private)"
echo -e "  ${COLOR_GREEN}Pulled${COLOR_RESET}             : $SYNCED"
echo -e "  ${COLOR_GREEN}Cloned (new)${COLOR_RESET}       : $CLONED"
echo -e "  ${COLOR_YELLOW}Skipped${COLOR_RESET}            : $SKIPPED"
echo -e "  ${COLOR_RED}Failed${COLOR_RESET}             : $FAILED"

echo ""
echo "✔ Sync complete!"
echo ""

if [[ $FAILED -gt 0 ]]; then
  exit 1
fi