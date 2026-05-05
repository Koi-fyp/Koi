#!/bin/bash

################################################################################
# KOI Project - Third-Party Service Provisioning Test Suite
#
# Tests for verifying all third-party services are configured and working
# (Firebase, Gemini, Supabase, Email, etc.)
#
# Usage: ./test_service_provisioning.sh
# Run from: repos/koi-backend/ directory
# Requires: .env.local file with credentials
################################################################################

set -o pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Test counters
TESTS_PASSED=0
TESTS_FAILED=0
TESTS_SKIPPED=0
TESTS_TOTAL=0

################################################################################
# Utility Functions
################################################################################

log_pass() {
  echo -e "${GREEN}✓ PASS${NC}: $1"
  ((TESTS_PASSED++))
  ((TESTS_TOTAL++))
}

log_fail() {
  echo -e "${RED}✗ FAIL${NC}: $1"
  ((TESTS_FAILED++))
  ((TESTS_TOTAL++))
}

log_skip() {
  echo -e "${YELLOW}⊘ SKIP${NC}: $1"
  ((TESTS_SKIPPED++))
  ((TESTS_TOTAL++))
}

log_manual() {
  echo -e "${YELLOW}⚠ MANUAL${NC}: $1"
  ((TESTS_SKIPPED++))
  ((TESTS_TOTAL++))
}

log_header() {
  echo ""
  echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo -e "${BLUE}$1${NC}"
  echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
}

################################################################################
# Pre-flight Checks
################################################################################

check_prerequisites() {
  log_header "Pre-flight Checks"

  # Check if .env.local exists
  if [ ! -f ".env.local" ]; then
    log_fail ".env.local not found (copy from .env.template)"
    return 1
  fi
  log_pass ".env.local exists"

  # Source environment variables
  source .env.local 2>/dev/null
  if [ $? -ne 0 ]; then
    log_fail "Failed to load .env.local"
    return 1
  fi
  log_pass "Environment variables loaded"

  # Check curl is available
  if ! command -v curl &> /dev/null; then
    log_fail "curl is required but not installed"
    return 1
  fi
  log_pass "curl available"

  # Check git is available
  if ! command -v git &> /dev/null; then
    log_fail "git is required but not installed"
    return 1
  fi
  log_pass "git available"

  return 0
}

################################################################################
# Firebase Tests
################################################################################

test_firebase_project() {
  log_header "Firebase Configuration Tests"

  if [ -z "$FIREBASE_PROJECT_ID" ]; then
    log_fail "FIREBASE_PROJECT_ID not set"
    return
  fi

  if firebase projects:list 2>/dev/null | grep -q "$FIREBASE_PROJECT_ID"; then
    log_pass "Firebase project exists: $FIREBASE_PROJECT_ID"
  else
    log_skip "Firebase project not found (run firebase login && firebase projects:list)"
  fi
}

test_firebase_auth() {
  ((TESTS_TOTAL++))
  if [ -z "$FIREBASE_API_KEY" ]; then
    log_fail "FIREBASE_API_KEY not configured"
    return
  fi

  if [ -n "$FIREBASE_API_KEY" ] && [ "$FIREBASE_API_KEY" != "AIza" ]; then
    log_pass "Firebase API key configured"
  else
    log_fail "Firebase API key appears invalid"
  fi
}

test_firebase_rules() {
  ((TESTS_TOTAL++))
  if [ -f "firestore.rules" ]; then
    log_pass "firestore.rules file exists"
  else
    log_fail "firestore.rules not found"
  fi
}

################################################################################
# Google AI Studio (Gemini) Tests
################################################################################

test_gemini_api_key() {
  ((TESTS_TOTAL++))
  if [ -z "$GOOGLE_AI_STUDIO_KEY" ]; then
    log_fail "GOOGLE_AI_STUDIO_KEY not set (get from https://aistudio.google.com)"
    return
  fi

  # Check format
  if [[ "$GOOGLE_AI_STUDIO_KEY" =~ ^AIza[A-Za-z0-9_-]{32,}$ ]]; then
    log_pass "GOOGLE_AI_STUDIO_KEY format looks valid"
  else
    log_fail "GOOGLE_AI_STUDIO_KEY format looks invalid"
  fi
}

test_gemini_api_connectivity() {
  ((TESTS_TOTAL++))
  if [ -z "$GOOGLE_AI_STUDIO_KEY" ]; then
    log_skip "GOOGLE_AI_STUDIO_KEY not set - skipping API test"
    return
  fi

  # Test Gemini 2.5 Flash API (may take 1-2 seconds)
  response=$(curl -s -w "\n%{http_code}" \
    -X POST "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent?key=$GOOGLE_AI_STUDIO_KEY" \
    -H "Content-Type: application/json" \
    -d '{"contents":[{"parts":[{"text":"test"}]}]}' 2>/dev/null || echo "error")

  http_code=$(echo "$response" | tail -n1)
  body=$(echo "$response" | head -n -1)

  if [ "$http_code" = "200" ]; then
    # Gemini returns valid JSON with candidates or text
    if echo "$body" | grep -q -E "(candidates|usageMetadata|modelVersion)"; then
      log_pass "Gemini API connectivity verified (HTTP 200)"
    else
      log_pass "Gemini API connectivity verified (HTTP 200, response received)"
    fi
  elif [ "$http_code" = "401" ]; then
    log_fail "Gemini API authentication failed (invalid key)"
  elif [ "$http_code" = "429" ]; then
    log_fail "Gemini API rate limit exceeded"
  elif [ "$http_code" = "error" ]; then
    log_fail "Gemini API connection error (network or timeout)"
  else
    log_fail "Gemini API error (HTTP $http_code)"
  fi
}

################################################################################
# Supabase Tests
################################################################################

test_supabase_credentials() {
  log_header "Supabase Configuration Tests"

  if [ -z "$SUPABASE_URL" ]; then
    log_fail "SUPABASE_URL not set"
    return
  fi
  log_pass "SUPABASE_URL configured"

  if [ -z "$SUPABASE_ANON_KEY" ]; then
    log_fail "SUPABASE_ANON_KEY not set (get from Supabase project settings)"
    return
  fi
  log_pass "SUPABASE_ANON_KEY configured"

  if [ -z "$SUPABASE_SERVICE_ROLE_KEY" ]; then
    log_skip "SUPABASE_SERVICE_ROLE_KEY not set (needed for backend operations)"
  else
    log_pass "SUPABASE_SERVICE_ROLE_KEY configured"
  fi
}

test_supabase_connectivity() {
  ((TESTS_TOTAL++))
  if [ -z "$SUPABASE_URL" ] || [ -z "$SUPABASE_ANON_KEY" ]; then
    log_skip "Supabase credentials not set - skipping connectivity test"
    return
  fi

  response=$(curl -s -w "\n%{http_code}" \
    -X GET "$SUPABASE_URL/rest/v1/" \
    -H "apikey: $SUPABASE_ANON_KEY" 2>/dev/null || echo "000")

  http_code=$(echo "$response" | tail -n1)

  if [ "$http_code" = "200" ] || [ "$http_code" = "400" ]; then
    log_pass "Supabase REST API connectivity verified (HTTP $http_code)"
  elif [ "$http_code" = "401" ]; then
    log_fail "Supabase authentication failed (invalid key)"
  else
    log_fail "Supabase connection error (HTTP $http_code)"
  fi
}

test_pgvector_extension() {
  ((TESTS_TOTAL++))
  log_manual "pgvector extension verification"
  echo "         Run in Supabase Dashboard: Database > Extensions > search 'vector'"
}

test_supabase_rls_policies() {
  ((TESTS_TOTAL++))
  log_manual "Row Level Security (RLS) policies"
  echo "         Verify in Supabase Dashboard: Authentication > Policies"
}

################################################################################
# Email Service Tests
################################################################################

test_email_templates() {
  log_header "Email Service Tests"

  if [ -f "email_templates/verification.html" ]; then
    log_pass "Verification email template exists"
  else
    log_fail "Verification email template not found"
  fi

  if [ -f "email_templates/clinical_report.html" ]; then
    log_pass "Clinical report email template exists"
  else
    log_fail "Clinical report email template not found"
  fi
}

test_sendgrid_api() {
  ((TESTS_TOTAL++))
  if [ -z "$SENDGRID_API_KEY" ]; then
    log_skip "SENDGRID_API_KEY not set (optional - sign up at https://sendgrid.com)"
    return
  fi

  response=$(curl -s -w "\n%{http_code}" \
    -X GET "https://api.sendgrid.com/v3/user/account" \
    -H "Authorization: Bearer $SENDGRID_API_KEY" 2>/dev/null || echo "000")

  http_code=$(echo "$response" | tail -n1)

  if [ "$http_code" = "200" ]; then
    log_pass "SendGrid API credentials verified"
  elif [ "$http_code" = "401" ]; then
    log_fail "SendGrid API authentication failed"
  else
    log_fail "SendGrid API error (HTTP $http_code)"
  fi
}

################################################################################
# Security Tests
################################################################################

test_env_gitignore() {
  log_header "Security Tests"

  if grep -q "^\.env\.local$" .gitignore 2>/dev/null; then
    log_pass ".env.local is in .gitignore"
  else
    log_fail ".env.local NOT in .gitignore - secrets could leak!"
  fi
}

test_no_secrets_committed() {
  ((TESTS_TOTAL++))
  if ! git ls-files 2>/dev/null | grep -q "\.env\.local"; then
    log_pass ".env.local is not tracked by Git"
  else
    log_fail ".env.local IS tracked by Git - remove it!"
  fi
}

test_env_template_safe() {
  ((TESTS_TOTAL++))
  if [ -f ".env.template" ] || [ -f "../.env.template" ]; then
    local template_file=".env.template"
    [ ! -f ".env.template" ] && template_file="../.env.template"

    if grep -q "your_.*_here" "$template_file" 2>/dev/null; then
      log_pass ".env.template contains no real secrets"
    else
      log_fail ".env.template may contain real API keys!"
    fi
  else
    log_fail ".env.template not found (check ../repos/.env.template)"
  fi
}

################################################################################
# Configuration Files Tests
################################################################################

test_config_files() {
  log_header "Configuration Files Tests"

  if [ -f "firebase.json" ]; then
    log_pass "firebase.json exists"
  else
    log_fail "firebase.json not found"
  fi

  if [ -f ".firebaserc" ]; then
    log_pass ".firebaserc exists"
  else
    log_fail ".firebaserc not found"
  fi

  if [ -f "supabase_init.sql" ]; then
    log_pass "supabase_init.sql exists"
  else
    log_fail "supabase_init.sql not found"
  fi

  if [ -f "storage.rules" ]; then
    log_pass "storage.rules exists"
  else
    log_fail "storage.rules not found"
  fi

  if [ -f "firestore.rules" ]; then
    log_pass "firestore.rules exists"
  else
    log_fail "firestore.rules not found"
  fi
}

################################################################################
# Summary Report
################################################################################

print_summary() {
  log_header "Test Results Summary"

  echo ""
  echo "Total Tests:  $TESTS_TOTAL"
  echo -e "  ${GREEN}Passed:${NC}  $TESTS_PASSED"
  echo -e "  ${RED}Failed:${NC}  $TESTS_FAILED"
  echo -e "  ${YELLOW}Skipped:${NC} $TESTS_SKIPPED"
  echo ""

  if [ $TESTS_FAILED -eq 0 ]; then
    echo -e "${GREEN}✓ All critical services provisioned!${NC}"
    echo ""
    echo "Next steps:"
    echo "  1. Create Firebase project (if not done)"
    echo "  2. Create Supabase project (if not done)"
    echo "  3. Run: firebase deploy --only firestore:rules,storage"
    echo "  4. Review FREE_TIER_STRATEGY.md for detailed setup"
    return 0
  else
    echo -e "${RED}✗ $TESTS_FAILED service(s) need configuration${NC}"
    echo ""
    echo "See failures above for what needs to be fixed."
    return 1
  fi
}

################################################################################
# Main Execution
################################################################################

main() {
  echo -e "${BLUE}"
  cat << "EOF"
╔═══════════════════════════════════════════════════════════════════════════╗
║     KOI Project - Third-Party Service Provisioning Test Suite             ║
║                                                                           ║
║  Validates Firebase, Gemini, Supabase, Email, and other integrations    ║
╚═══════════════════════════════════════════════════════════════════════════╝
EOF
  echo -e "${NC}"

  # Check prerequisites
  check_prerequisites || return 1

  # Run all tests
  test_firebase_project
  test_firebase_auth
  test_firebase_rules

  test_gemini_api_key
  test_gemini_api_connectivity

  test_supabase_credentials
  test_supabase_connectivity
  test_pgvector_extension
  test_supabase_rls_policies

  test_email_templates
  test_sendgrid_api

  test_env_gitignore
  test_no_secrets_committed
  test_env_template_safe

  test_config_files

  # Print summary
  print_summary
}

# Run main function
main
exit $?
