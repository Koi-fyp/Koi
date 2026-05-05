# KOI Project - Third-Party Services Configuration Guide

## 📋 Table of Contents
1. [Firebase Setup](#firebase-setup)
2. [Google Cloud - Gemini API](#google-cloud---gemini-api)
3. [Supabase Setup](#supabase-setup)
4. [Email Service Setup](#email-service-setup)
5. [Vercel Deployment](#vercel-deployment)
6. [Environment Variables](#environment-variables)
7. [Security & Compliance](#security--compliance)
8. [Monitoring & Troubleshooting](#monitoring--troubleshooting)

---

## Firebase Setup

### Prerequisites
- Google account with billing enabled
- Firebase CLI installed: `npm install -g firebase-tools`

### Step 1: Create Firebase Project

1. Go to [Firebase Console](https://console.firebase.google.com)
2. Click "Add project"
3. Project name: `koi-companion-fyp`
4. Enable Google Analytics (optional)
5. Click "Create project"

### Step 2: Enable Firebase Services

#### Authentication
```bash
# In Firebase Console:
# 1. Go to Build → Authentication
# 2. Click "Get Started"
# 3. Enable providers:
#    - Email/Password
#    - Anonymous
#    - Google (optional)
#    - Apple (optional)
```

#### Cloud Firestore
```bash
# In Firebase Console:
# 1. Go to Build → Firestore Database
# 2. Click "Create database"
# 3. Start in test mode (we'll secure it later)
# 4. Select region: us-central1 (or closest to your users)
# 5. Click "Create"
```

#### Cloud Functions
```bash
# In Firebase Console:
# 1. Go to Build → Functions
# 2. Click "Get Started"
# 3. Deploy from CLI (see below)
```

#### Cloud Storage
```bash
# In Firebase Console:
# 1. Go to Build → Storage
# 2. Click "Get Started"
# 3. Select test mode
# 4. Choose default bucket location
# 5. Click "Done"

# Add CORS configuration:
firebase storage:cors:set storage.cors.json
```

**storage.cors.json**:
```json
[
  {
    "origin": [
      "http://localhost:3000",
      "http://localhost:5000",
      "https://koi-companion.com"
    ],
    "method": ["GET", "HEAD", "DELETE"],
    "responseHeader": ["Content-Type", "Authorization"],
    "maxAgeSeconds": 3600
  }
]
```

### Step 3: Get Firebase Credentials

```bash
# 1. Go to Project Settings (⚙️)
# 2. Select "Service Accounts" tab
# 3. Click "Generate new private key"
# 4. Save as `firebase-admin-key.json`
# 5. Add to `.gitignore` (never commit!)

# For web app:
# 1. Click "Add app" → Web
# 2. Copy the config object to environment variables
```

### Step 4: Set Billing Alerts

```bash
# In Firebase Console:
# 1. Go to Project Settings
# 2. Click "Billing"
# 3. Set budget alerts:
#    - $50 (warning)
#    - $100 (critical)
#    - $200 (shutdown)
```

### Step 5: Deploy Firebase Configuration

```bash
# Login to Firebase CLI
firebase login

# Initialize Firebase in koi-backend repo
cd repos/koi-backend
firebase init

# Deploy security rules
firebase deploy --only firestore:rules,storage

# Deploy Cloud Functions
firebase deploy --only functions
```

---

## Google Cloud - Gemini API

### Step 1: Create Google Cloud Project

1. Go to [Google Cloud Console](https://console.cloud.google.com)
2. Select an organization (or create one)
3. Click "Create Project"
4. Project name: `koi-companion-gemini`
5. Click "Create"

### Step 2: Enable Gemini API

```bash
# In Google Cloud Console:
# 1. Go to APIs & Services → Enabled APIs
# 2. Click "+ Enable APIs and Services"
# 3. Search for "Generative Language API"
# 4. Click "Enable"

# Wait for API to enable (5-10 minutes)
```

### Step 3: Create API Key

```bash
# In Google Cloud Console:
# 1. Go to APIs & Services → Credentials
# 2. Click "Create Credentials" → "API Key"
# 3. Name it: `koi-gemini-key`
# 4. Copy the key
# 5. Add to .env.local:
#    GEMINI_API_KEY=your_key_here
```

### Step 4: Configure API Quotas

```bash
# In Google Cloud Console:
# 1. Go to APIs & Services → Quotas
# 2. Search for "generativelanguage.googleapis.com"
# 3. Click on it → Edit Quotas
# 4. Set rate limit: 60 requests/minute
# 5. Click "Update"
```

### Step 5: Set Billing Alert

```bash
# In Google Cloud Console:
# 1. Go to Billing
# 2. Set budget alerts:
#    - $50/month (warning)
#    - $100/month (critical)
```

### Step 6: Configure Safety Settings

In your backend code:
```javascript
const generationConfig = {
  temperature: 0.7,
  topP: 0.95,
  topK: 40,
  maxOutputTokens: 1024,
};

const safetySettings = [
  {
    category: "HARM_CATEGORY_SEXUALLY_EXPLICIT",
    threshold: "BLOCK_MEDIUM_AND_ABOVE",
  },
  {
    category: "HARM_CATEGORY_HATE_SPEECH",
    threshold: "BLOCK_MEDIUM_AND_ABOVE",
  },
  {
    category: "HARM_CATEGORY_HARASSMENT",
    threshold: "BLOCK_MEDIUM_AND_ABOVE",
  },
  {
    category: "HARM_CATEGORY_DANGEROUS_CONTENT",
    threshold: "BLOCK_MEDIUM_AND_ABOVE",
  },
];
```

---

## Supabase Setup

### Step 1: Create Supabase Project

1. Go to [Supabase](https://supabase.com)
2. Sign in or create account
3. Click "New project"
4. Project name: `koi-analytics`
5. Database password: (generate strong password)
6. Region: (closest to your users)
7. Click "Create new project"

### Step 2: Enable Extensions

```bash
# In Supabase Dashboard:
# 1. Go to Marketplace
# 2. Install:
#    - pgvector (for semantic search)
#    - pg_stat_statements (for performance monitoring)
#    - uuid-ossp (for UUID generation)
```

### Step 3: Run Initialization SQL

```bash
# In Supabase Dashboard:
# 1. Go to SQL Editor
# 2. Click "New query"
# 3. Copy contents of supabase_init.sql
# 4. Paste into editor
# 5. Click "Run"
```

### Step 4: Configure Row Level Security (RLS)

All policies are configured in `supabase_init.sql`. Verify in dashboard:

```bash
# In Supabase Dashboard:
# 1. Go to Authentication → Policies
# 2. Verify all tables have RLS enabled
# 3. Check policies for each table
```

### Step 5: Get API Keys

```bash
# In Supabase Dashboard:
# 1. Go to Settings → API
# 2. Copy:
#    - Project URL → SUPABASE_URL
#    - anon key → SUPABASE_ANON_KEY
#    - service_role key → SUPABASE_SERVICE_ROLE_KEY
```

### Step 6: Configure Connection Pooling

```bash
# In Supabase Dashboard:
# 1. Go to Database → Connection Pooling
# 2. Mode: transaction
# 3. Max connections: 5
# 4. Connection timeout: 30s
```

---

## Email Service Setup

### Option A: SendGrid

#### Step 1: Create SendGrid Account
1. Go to [SendGrid](https://sendgrid.com)
2. Sign up for free tier
3. Verify email address

#### Step 2: Generate API Key
```bash
# In SendGrid Dashboard:
# 1. Go to Settings → API Keys
# 2. Click "Create API Key"
# 3. Name: koi-app
# 4. Permissions: Full Access
# 5. Copy key → SENDGRID_API_KEY
```

#### Step 3: Verify Sender Domain
```bash
# In SendGrid Dashboard:
# 1. Go to Settings → Sender Authentication
# 2. Click "Verify a Domain"
# 3. Enter domain: koi-companion.com
# 4. Add DNS records (follow instructions)
# 5. Verify (can take 24-48 hours)
```

### Option B: AWS SES

#### Step 1: Create AWS Account
1. Go to [AWS Console](https://console.aws.amazon.com)
2. Create account or sign in

#### Step 2: Verify Email Address
```bash
# In AWS Console:
# 1. Go to Simple Email Service (SES)
# 2. Click "Verified identities"
# 3. Click "Create identity"
# 4. Email address: noreply@koi-companion.com
# 5. Check email for verification link
# 6. Click to verify
```

#### Step 3: Create SMTP Credentials
```bash
# In AWS Console SES:
# 1. Go to Account Dashboard
# 2. Click "Create SMTP credentials"
# 3. Copy credentials:
#    - AWS_SES_ACCESS_KEY_ID
#    - AWS_SES_SECRET_ACCESS_KEY
#    - SMTP endpoint
```

#### Step 4: Request Production Access
```bash
# In AWS Console SES:
# 1. Dashboard shows: "You're in the sandbox"
# 2. Click "Request production access"
# 3. Fill form and submit
# 4. Wait for approval (usually 24 hours)
```

### Email Template Setup

Templates are in `email_templates/`:
- `verification.html` - Email verification
- `clinical_report.html` - Report delivery

To use in code:
```javascript
const fs = require('fs');
const Handlebars = require('handlebars');

const template = fs.readFileSync('email_templates/verification.html', 'utf8');
const compiled = Handlebars.compile(template);
const html = compiled({
  VERIFICATION_CODE: '123456',
  VERIFICATION_URL: 'https://app.koi-companion.com/verify?code=123456'
});
```

---

## Vercel Deployment

### Step 1: Connect Repository

1. Go to [Vercel](https://vercel.com)
2. Sign in with GitHub
3. Click "New Project"
4. Select `koi-web` repository
5. Click "Import"

### Step 2: Configure Project

```bash
# In Vercel Dashboard:
# 1. Project name: koi-web
# 2. Framework preset: Next.js
# 3. Root directory: .
# 4. Build command: npm run build
# 5. Output directory: .next
```

### Step 3: Add Environment Variables

```bash
# In Vercel Project Settings:
# 1. Go to Settings → Environment Variables
# 2. Add:
#    - NEXT_PUBLIC_FIREBASE_CONFIG
#    - NEXT_PUBLIC_API_URL
#    - NEXT_PUBLIC_GEMINI_API_KEY (if safe)
#    - All public variables (NEXT_PUBLIC_*)
```

### Step 4: Enable Preview Deployments

```bash
# In Vercel Project Settings:
# 1. Go to Settings → Git
# 2. Preview Deployments: Enabled
# 3. Comments: Enabled
#    (Automatically comment on PRs with deploy preview)
```

### Step 5: Set Custom Domain

```bash
# In Vercel Project Settings:
# 1. Go to Settings → Domains
# 2. Add custom domain: koi-companion.com
# 3. Add CNAME record to DNS:
#    Name: koi-web
#    Value: cname.vercel.com
#    TTL: 3600
# 4. Verify (takes 5-10 minutes)
```

---

## Environment Variables

### Setup .env.local

Copy `.env.template` to `.env.local` and fill in actual values:

```bash
# Backend (.env.local in koi-backend)
cp .env.template .env.local
# Edit with actual credentials

# Web (.env.local in koi-web)
cp .env.template .env.local
# Edit with public variables

# Mobile (koi-mobile)
# Create config.json with public variables
```

### Never Commit Secrets

Add to `.gitignore`:
```
.env
.env.local
.env.*.local
firebase-admin-key.json
credentials.json
secrets/
```

---

## Security & Compliance

### API Key Management

1. **Rotate Quarterly**
   ```bash
   # Create new key, update env vars, disable old key
   # Then delete old key after confirming new one works
   ```

2. **Separate Keys for Environments**
   ```
   Development: koi-gemini-key-dev
   Staging: koi-gemini-key-staging
   Production: koi-gemini-key-prod
   ```

3. **Principle of Least Privilege**
   - Each key has only necessary permissions
   - Backend: Full access to all services
   - Frontend: Only public/anon access
   - Mobile: Limited API access

4. **Enable MFA**
   - Firebase: Enable 2FA on all admin accounts
   - Google Cloud: Enable 2FA
   - Supabase: Enable 2FA
   - Vercel: Enable 2FA

### Data Privacy

- All data encrypted in transit (HTTPS)
- Firestore rules restrict data access
- Supabase RLS policies enforce row-level security
- Email templates don't contain PII
- Analytics uses hashed user IDs

### Compliance

- HIPAA compliance (if handling medical data)
  - Enable encryption at rest in Firebase
  - Set up audit logging
  - Implement access controls

- GDPR compliance (if EU users)
  - Data deletion on request
  - Right to export data
  - Clear privacy policy

---

## Monitoring & Troubleshooting

### Firebase Monitoring

```bash
# Check quotas
firebase projects:list

# Monitor functions
firebase functions:log

# Check errors
firebase debug firestore
```

### Gemini API Monitoring

```bash
# Check quota usage in Google Cloud Console:
# 1. APIs & Services → Quotas
# 2. generativelanguage.googleapis.com
# 3. View "Quota Usage"

# Monitor billing:
# 1. Billing → Budgets and alerts
# 2. Set alerts for overspend
```

### Supabase Monitoring

```bash
# In Supabase Dashboard:
# 1. Go to Monitoring
# 2. View:
#    - Database CPU usage
#    - Connection count
#    - Query performance
#    - API usage
```

### Common Issues

#### Firebase Auth Not Working
```bash
# Check:
# 1. API Key is valid
# 2. Auth domain is correct
# 3. Email/Password provider is enabled
# 4. CORS is configured
```

#### Gemini API Rate Limit
```bash
# Solution:
# 1. Implement request queuing
# 2. Add exponential backoff
# 3. Request quota increase from Google Cloud
```

#### Supabase Connection Issues
```bash
# Check:
# 1. Connection pooling is enabled
# 2. Connection timeout is reasonable
# 3. Database isn't overloaded
# 4. RLS policies allow access
```

---

## Maintenance Schedule

- **Weekly**: Check API usage and cost trends
- **Monthly**: Review security alerts and update dependencies
- **Quarterly**: Rotate API keys and review access logs
- **Annually**: Audit all security configurations and compliance

---

**Next Steps**: Follow this guide to configure all services, then run `verify_services.sh` to test connectivity.
