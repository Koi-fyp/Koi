#!/bin/bash

################################################################################
# KOI Project - Third-Party Services Verification Script
#
# This script validates connectivity and configuration for all third-party
# services used by the KOI project: Firebase, Google Cloud Gemini, Supabase,
# Email services (SendGrid/SES), and Vercel deployment.
#
# Usage: ./verify_services.sh
# Dependencies: curl, firebase-cli, git
################################################################################

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Counters
PASSED=0
FAILED=0
SKIPPED=0
WARNINGS=0

# Configuration
ENV_FILE=".env.local"
TIMEOUT=10

################################################################################
# Utility Functions
################################################################################

log_header() {
  echo -e "\n${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo -e "${BLUE}$1${NC}"
  echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
}

log_pass() {
  echo -e "${GREEN}✓${NC} $1"
  ((PASSED++))
}

log_fail() {
  echo -e "${RED}✗${NC} $1"
  ((FAILED++))
}

log_skip() {
  echo -e "${YELLOW}⊘${NC} $1"
  ((SKIPPED++))
}

log_warn() {
  echo -e "${YELLOW}⚠${NC} $1"
  ((WARNINGS++))
}

log_info() {
  echo "  $1"
}

# Load environment variables
load_env() {
  if [ -f "$ENV_FILE" ]; then
    export $(cat "$ENV_FILE" | grep -v '#' | xargs)
    log_pass "Environment variables loaded from $ENV_FILE"
  else
    log_warn "Environment file not found: $ENV_FILE"
  fi
}

################################################################################
# Firebase Verification
################################################################################

verify_firebase() {
  log_header "Firebase Verification"

  # Check Firebase CLI
  if ! command -v firebase &> /dev/null; then
    log_fail "Firebase CLI not installed"
    log_info "Install with: npm install -g firebase-tools"
    return
  fi
  log_pass "Firebase CLI installed"

  # Check if logged in
  if ! firebase projects:list &> /dev/null; then
    log_fail "Firebase authentication failed"
    log_info "Run: firebase login"
    return
  fi
  log_pass "Firebase authentication successful"

  # Check firebase.json exists
  if [ ! -f "firebase.json" ]; then
    log_warn "firebase.json not found in current directory"
    return
  fi
  log_pass "firebase.json found"

  # Check .firebaserc exists
  if [ ! -f ".firebaserc" ]; then
    log_warn ".firebaserc not found in current directory"
    return
  fi
  log_pass ".firebaserc found"

  # Check if default project exists
  DEFAULT_PROJECT=$(grep -o '"default": "[^"]*' .firebaserc | cut -d'"' -f4)
  if [ -z "$DEFAULT_PROJECT" ]; then
    log_warn "No default Firebase project configured in .firebaserc"
    return
  fi
  log_pass "Default Firebase project: $DEFAULT_PROJECT"

  # List all projects
  PROJECTS=$(firebase projects:list 2>/dev/null | grep -oP '✓\s+\K.*' || echo "")
  if [ -z "$PROJECTS" ]; then
    log_warn "No Firebase projects found (or error listing projects)"
    return
  fi
  log_info "Available Firebase projects:"
  echo "$PROJECTS" | while read project; do
    log_info "  - $project"
  done
}

################################################################################
# Google Cloud Gemini API Verification
################################################################################

verify_gemini() {
  log_header "Google Cloud Gemini API Verification"

  # Check API key
  if [ -z "$GEMINI_API_KEY" ]; then
    log_fail "GEMINI_API_KEY not set in environment"
    log_info "Add to $ENV_FILE: GEMINI_API_KEY=<your_key>"
    return
  fi
  log_pass "GEMINI_API_KEY is set"

  # Test API connectivity
  local api_url="https://generativelanguage.googleapis.com/v1beta/models/gemini-1.5-flash:generateContent"
  local response=$(curl -s -w "\n%{http_code}" \
    -X POST "$api_url" \
    -H "Content-Type: application/json" \
    -H "x-goog-api-key: $GEMINI_API_KEY" \
    -d '{
      "contents": [{
        "parts": [{"text": "Say hello in one word"}]
      }]
    }' \
    --max-time $TIMEOUT 2>/dev/null || echo "000")

  local http_code=$(echo "$response" | tail -n1)

  if [ "$http_code" = "200" ]; then
    log_pass "Gemini API connectivity test successful (HTTP 200)"
  elif [ "$http_code" = "401" ]; then
    log_fail "Gemini API authentication failed (HTTP 401) - Invalid API key"
  elif [ "$http_code" = "429" ]; then
    log_warn "Gemini API rate limit exceeded (HTTP 429)"
  elif [ "$http_code" = "000" ]; then
    log_fail "Gemini API connection failed - Network error or timeout"
  else
    log_warn "Gemini API returned HTTP $http_code"
  fi

  # Check API key format
  if [[ "$GEMINI_API_KEY" =~ ^[A-Za-z0-9_-]{40,}$ ]]; then
    log_pass "GEMINI_API_KEY format looks valid"
  else
    log_warn "GEMINI_API_KEY format may be invalid"
  fi
}

################################################################################
# Supabase Verification
################################################################################

verify_supabase() {
  log_header "Supabase Verification"

  # Check connection variables
  if [ -z "$SUPABASE_URL" ]; then
    log_fail "SUPABASE_URL not set in environment"
    log_info "Add to $ENV_FILE: SUPABASE_URL=https://<project>.supabase.co"
    return
  fi
  log_pass "SUPABASE_URL is set: $SUPABASE_URL"

  if [ -z "$SUPABASE_ANON_KEY" ]; then
    log_fail "SUPABASE_ANON_KEY not set in environment"
    log_info "Add to $ENV_FILE: SUPABASE_ANON_KEY=<your_anon_key>"
    return
  fi
  log_pass "SUPABASE_ANON_KEY is set (${#SUPABASE_ANON_KEY} chars)"

  if [ -z "$SUPABASE_SERVICE_ROLE_KEY" ]; then
    log_warn "SUPABASE_SERVICE_ROLE_KEY not set - some operations will fail"
  else
    log_pass "SUPABASE_SERVICE_ROLE_KEY is set (${#SUPABASE_SERVICE_ROLE_KEY} chars)"
  fi

  # Test REST API connectivity
  local response=$(curl -s -w "\n%{http_code}" \
    -X GET "$SUPABASE_URL/rest/v1/" \
    -H "apikey: $SUPABASE_ANON_KEY" \
    --max-time $TIMEOUT 2>/dev/null || echo "000")

  local http_code=$(echo "$response" | tail -n1)

  if [ "$http_code" = "200" ] || [ "$http_code" = "400" ]; then
    log_pass "Supabase REST API connectivity test successful (HTTP $http_code)"
  elif [ "$http_code" = "401" ]; then
    log_fail "Supabase authentication failed (HTTP 401) - Invalid API key"
  elif [ "$http_code" = "000" ]; then
    log_fail "Supabase connection failed - Network error or timeout"
  else
    log_warn "Supabase REST API returned HTTP $http_code"
  fi

  # Check for pgvector extension (if service role key available)
  if [ ! -z "$SUPABASE_SERVICE_ROLE_KEY" ]; then
    local pgvector_check=$(curl -s -X GET \
      "$SUPABASE_URL/rest/v1/rpc/check_extension" \
      -H "apikey: $SUPABASE_SERVICE_ROLE_KEY" \
      -H "Authorization: Bearer $SUPABASE_SERVICE_ROLE_KEY" \
      --max-time $TIMEOUT 2>/dev/null || echo "")

    if [ -z "$pgvector_check" ]; then
      log_info "pgvector extension check skipped (requires custom RPC)"
    fi
  fi
}

################################################################################
# Email Service Verification
################################################################################

verify_email() {
  log_header "Email Service Verification"

  # Check SendGrid
  if [ ! -z "$SENDGRID_API_KEY" ]; then
    log_info "SendGrid API key found"

    # Test SendGrid connectivity
    local response=$(curl -s -w "\n%{http_code}" \
      -X GET "https://api.sendgrid.com/v3/user/account" \
      -H "Authorization: Bearer $SENDGRID_API_KEY" \
      --max-time $TIMEOUT 2>/dev/null || echo "000")

    local http_code=$(echo "$response" | tail -n1)

    if [ "$http_code" = "200" ]; then
      log_pass "SendGrid API connectivity test successful (HTTP 200)"
    elif [ "$http_code" = "401" ]; then
      log_fail "SendGrid authentication failed (HTTP 401) - Invalid API key"
    elif [ "$http_code" = "000" ]; then
      log_fail "SendGrid connection failed - Network error or timeout"
    else
      log_warn "SendGrid returned HTTP $http_code"
    fi
  fi

  # Check AWS SES
  if [ ! -z "$AWS_SES_ACCESS_KEY_ID" ] && [ ! -z "$AWS_SES_SECRET_ACCESS_KEY" ]; then
    log_info "AWS SES credentials found"

    if command -v aws &> /dev/null; then
      local ses_check=$(aws ses describe-configuration-set \
        --configuration-set-name default \
        --region ${AWS_REGION:-us-east-1} 2>/dev/null || echo "")

      if [ ! -z "$ses_check" ]; then
        log_pass "AWS SES connectivity test successful"
      else
        log_warn "AWS SES connection check failed (check region and credentials)"
      fi
    else
      log_skip "AWS CLI not installed - skipping SES test"
      log_info "Install AWS CLI for full SES verification"
    fi
  fi

  # Check email templates
  if [ -f "email_templates/verification.html" ]; then
    log_pass "Verification email template found"
  else
    log_warn "Verification email template not found"
  fi

  if [ -f "email_templates/clinical_report.html" ]; then
    log_pass "Clinical report email template found"
  else
    log_warn "Clinical report email template not found"
  fi

  if [ -z "$SENDGRID_API_KEY" ] && [ -z "$AWS_SES_ACCESS_KEY_ID" ]; then
    log_warn "No email service configured"
    log_info "Add either SENDGRID_API_KEY or AWS_SES_ACCESS_KEY_ID to $ENV_FILE"
  fi
}

################################################################################
# Vercel Verification
################################################################################

verify_vercel() {
  log_header "Vercel Deployment Verification"

  # Check Vercel CLI
  if command -v vercel &> /dev/null; then
    log_pass "Vercel CLI installed"

    # Check if authenticated
    if vercel whoami &> /dev/null; then
      local vercel_user=$(vercel whoami 2>/dev/null)
      log_pass "Vercel authentication successful (User: $vercel_user)"
    else
      log_warn "Vercel CLI not authenticated"
      log_info "Run: vercel login"
    fi
  else
    log_skip "Vercel CLI not installed"
    log_info "Install with: npm install -g vercel"
  fi

  # Check Next.js configuration
  if [ -f "next.config.js" ] || [ -f "next.config.ts" ]; then
    log_pass "Next.js configuration found"
  else
    log_skip "Next.js configuration not found (expected in koi-web, not koi-backend)"
  fi

  # Check Vercel configuration
  if [ -f "vercel.json" ]; then
    log_pass "vercel.json configuration found"
  else
    log_info "No vercel.json found (using defaults)"
  fi
}

################################################################################
# Summary Report
################################################################################

print_summary() {
  log_header "Verification Summary"

  local total=$((PASSED + FAILED + SKIPPED))

  echo ""
  echo "Results:"
  echo -e "  ${GREEN}Passed:${NC}   $PASSED"
  echo -e "  ${RED}Failed:${NC}   $FAILED"
  echo -e "  ${YELLOW}Skipped:${NC}  $SKIPPED"
  echo -e "  ${YELLOW}Warnings:${NC} $WARNINGS"
  echo -e "  ${BLUE}Total:${NC}    $total"

  echo ""

  if [ $FAILED -eq 0 ]; then
    echo -e "${GREEN}✓ All critical services verified successfully!${NC}"

    if [ $WARNINGS -gt 0 ]; then
      echo -e "${YELLOW}⚠ Review $WARNINGS warning(s) above${NC}"
    fi

    return 0
  else
    echo -e "${RED}✗ $FAILED service(s) failed verification - see above for details${NC}"
    return 1
  fi
}

################################################################################
# Pre-flight Checks
################################################################################

precheck() {
  # Check curl is available
  if ! command -v curl &> /dev/null; then
    echo -e "${RED}✗ curl is required but not installed${NC}"
    exit 1
  fi

  # Check git is available
  if ! command -v git &> /dev/null; then
    echo -e "${RED}✗ git is required but not installed${NC}"
    exit 1
  fi
}

################################################################################
# Main Execution
################################################################################

main() {
  echo -e "${BLUE}"
  cat << "EOF"
╔═══════════════════════════════════════════════════════════════════════════╗
║            KOI Project - Third-Party Services Verification                ║
╚═══════════════════════════════════════════════════════════════════════════╝
EOF
  echo -e "${NC}"

  precheck
  load_env

  verify_firebase
  verify_gemini
  verify_supabase
  verify_email
  verify_vercel

  print_summary
}

# Run main function
main
exit $?
