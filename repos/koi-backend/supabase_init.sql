-- =============================================================================
-- KOI Project - Supabase Database Schema Initialization
-- =============================================================================
-- This script sets up the analytics database with pgvector for semantic search
-- and configures Row Level Security (RLS) policies
-- =============================================================================

-- Enable pgvector extension for semantic search
CREATE EXTENSION IF NOT EXISTS vector;

-- Enable UUID extension
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- =============================================================================
-- ANALYTICS EVENTS TABLE
-- =============================================================================
-- Stores anonymized analytics events for research and monitoring
CREATE TABLE IF NOT EXISTS analytics_events (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id_hash VARCHAR(64) NOT NULL,  -- SHA-256 hashed user ID
    event_type VARCHAR(50) NOT NULL,
    event_category VARCHAR(50),
    event_data JSONB DEFAULT '{}',
    device_type VARCHAR(20),  -- mobile, web, tablet
    os_type VARCHAR(20),  -- ios, android, windows, macos, linux
    app_version VARCHAR(20),
    timestamp TIMESTAMPTZ DEFAULT NOW(),
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Create indexes for analytics_events
CREATE INDEX idx_analytics_user_hash ON analytics_events(user_id_hash);
CREATE INDEX idx_analytics_event_type ON analytics_events(event_type);
CREATE INDEX idx_analytics_event_category ON analytics_events(event_category);
CREATE INDEX idx_analytics_timestamp ON analytics_events(timestamp DESC);
CREATE INDEX idx_analytics_device_type ON analytics_events(device_type);
CREATE INDEX idx_analytics_created_at ON analytics_events(created_at DESC);

-- =============================================================================
-- DIAGNOSTIC INTERACTIONS TABLE
-- =============================================================================
-- Logs interactions with diagnostic tools for model improvement
CREATE TABLE IF NOT EXISTS diagnostic_interactions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id_hash VARCHAR(64) NOT NULL,
    interaction_type VARCHAR(50) NOT NULL,  -- query, feedback, correction
    input_data JSONB,
    gemini_response JSONB,
    user_feedback JSONB,  -- rating, comments
    timestamp TIMESTAMPTZ DEFAULT NOW(),
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Create indexes for diagnostic_interactions
CREATE INDEX idx_diagnostic_user_hash ON diagnostic_interactions(user_id_hash);
CREATE INDEX idx_diagnostic_interaction_type ON diagnostic_interactions(interaction_type);
CREATE INDEX idx_diagnostic_timestamp ON diagnostic_interactions(timestamp DESC);

-- =============================================================================
-- EMBEDDINGS TABLE (for semantic search)
-- =============================================================================
-- Stores vector embeddings of user queries and medical data
CREATE TABLE IF NOT EXISTS embeddings (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    content TEXT NOT NULL,
    content_type VARCHAR(50),  -- query, article, symptom, diagnosis
    embedding vector(768),  -- Gemini embeddings are 768-dimensional
    metadata JSONB DEFAULT '{}',
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Create indexes for embeddings
CREATE INDEX idx_embeddings_content_type ON embeddings(content_type);
CREATE INDEX idx_embeddings_embedding ON embeddings USING ivfflat (embedding vector_cosine_ops) WITH (lists = 100);
CREATE INDEX idx_embeddings_created_at ON embeddings(created_at DESC);

-- =============================================================================
-- SYSTEM LOGS TABLE
-- =============================================================================
-- Logs system events and errors for monitoring
CREATE TABLE IF NOT EXISTS system_logs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    log_level VARCHAR(10),  -- DEBUG, INFO, WARN, ERROR, FATAL
    service_name VARCHAR(50),
    message TEXT,
    error_stack TEXT,
    context JSONB DEFAULT '{}',
    timestamp TIMESTAMPTZ DEFAULT NOW()
);

-- Create indexes for system_logs
CREATE INDEX idx_system_logs_log_level ON system_logs(log_level);
CREATE INDEX idx_system_logs_service_name ON system_logs(service_name);
CREATE INDEX idx_system_logs_timestamp ON system_logs(timestamp DESC);

-- =============================================================================
-- FEATURE FLAGS TABLE
-- =============================================================================
-- Manages feature rollouts and A/B testing
CREATE TABLE IF NOT EXISTS feature_flags (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    flag_name VARCHAR(100) UNIQUE NOT NULL,
    enabled BOOLEAN DEFAULT false,
    rollout_percentage INTEGER DEFAULT 0,  -- 0-100
    description TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Create indexes for feature_flags
CREATE INDEX idx_feature_flags_name ON feature_flags(flag_name);
CREATE INDEX idx_feature_flags_enabled ON feature_flags(enabled);

-- =============================================================================
-- USAGE QUOTA TABLE
-- =============================================================================
-- Tracks API usage for rate limiting and billing
CREATE TABLE IF NOT EXISTS usage_quota (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id_hash VARCHAR(64) NOT NULL,
    service_name VARCHAR(50),  -- gemini, supabase, firebase
    requests_count INTEGER DEFAULT 0,
    tokens_used INTEGER DEFAULT 0,
    cost DECIMAL(10, 4) DEFAULT 0.00,
    period_start TIMESTAMPTZ NOT NULL,
    period_end TIMESTAMPTZ NOT NULL,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Create indexes for usage_quota
CREATE INDEX idx_usage_quota_user_hash ON usage_quota(user_id_hash);
CREATE INDEX idx_usage_quota_service_name ON usage_quota(service_name);
CREATE INDEX idx_usage_quota_period ON usage_quota(period_start, period_end);

-- =============================================================================
-- ROW LEVEL SECURITY (RLS) POLICIES
-- =============================================================================

-- Enable RLS on all tables
ALTER TABLE analytics_events ENABLE ROW LEVEL SECURITY;
ALTER TABLE diagnostic_interactions ENABLE ROW LEVEL SECURITY;
ALTER TABLE embeddings ENABLE ROW LEVEL SECURITY;
ALTER TABLE system_logs ENABLE ROW LEVEL SECURITY;
ALTER TABLE feature_flags ENABLE ROW LEVEL SECURITY;
ALTER TABLE usage_quota ENABLE ROW LEVEL SECURITY;

-- =============================================================================
-- ANALYTICS EVENTS POLICIES
-- =============================================================================

-- Service role: Full access
CREATE POLICY "Service role full access on analytics_events"
    ON analytics_events
    FOR ALL
    TO service_role
    USING (true)
    WITH CHECK (true);

-- Anonymous role: Can only insert (anonymous analytics)
CREATE POLICY "Anon can insert analytics events"
    ON analytics_events
    FOR INSERT
    TO anon
    WITH CHECK (true);

-- Authenticated role: Can only view their own anonymized data
CREATE POLICY "Authenticated can view own analytics"
    ON analytics_events
    FOR SELECT
    TO authenticated
    USING (false);  -- Can't actually query individual events

-- =============================================================================
-- DIAGNOSTIC INTERACTIONS POLICIES
-- =============================================================================

-- Service role: Full access
CREATE POLICY "Service role full access on diagnostic_interactions"
    ON diagnostic_interactions
    FOR ALL
    TO service_role
    USING (true)
    WITH CHECK (true);

-- Anonymous role: Can insert their interactions
CREATE POLICY "Anon can insert diagnostic interactions"
    ON diagnostic_interactions
    FOR INSERT
    TO anon
    WITH CHECK (true);

-- =============================================================================
-- EMBEDDINGS POLICIES
-- =============================================================================

-- Service role: Full access
CREATE POLICY "Service role full access on embeddings"
    ON embeddings
    FOR ALL
    TO service_role
    USING (true)
    WITH CHECK (true);

-- Public read access to embeddings (for semantic search)
CREATE POLICY "Public can read embeddings"
    ON embeddings
    FOR SELECT
    TO public
    USING (true);

-- =============================================================================
-- SYSTEM LOGS POLICIES
-- =============================================================================

-- Service role only: Full access
CREATE POLICY "Service role only on system_logs"
    ON system_logs
    FOR ALL
    TO service_role
    USING (true)
    WITH CHECK (true);

-- Deny all other access to logs
CREATE POLICY "Deny all on system_logs"
    ON system_logs
    FOR ALL
    TO public, anon, authenticated
    USING (false)
    WITH CHECK (false);

-- =============================================================================
-- FEATURE FLAGS POLICIES
-- =============================================================================

-- Service role: Full access
CREATE POLICY "Service role full access on feature_flags"
    ON feature_flags
    FOR ALL
    TO service_role
    USING (true)
    WITH CHECK (true);

-- Public read access to feature flags
CREATE POLICY "Public read feature flags"
    ON feature_flags
    FOR SELECT
    TO public, authenticated, anon
    USING (true);

-- =============================================================================
-- USAGE QUOTA POLICIES
-- =============================================================================

-- Service role: Full access
CREATE POLICY "Service role full access on usage_quota"
    ON usage_quota
    FOR ALL
    TO service_role
    USING (true)
    WITH CHECK (true);

-- Deny all other access
CREATE POLICY "Deny all on usage_quota"
    ON usage_quota
    FOR ALL
    TO public, anon, authenticated
    USING (false)
    WITH CHECK (false);

-- =============================================================================
-- STORED PROCEDURES
-- =============================================================================

-- Function to log system events
CREATE OR REPLACE FUNCTION log_system_event(
    p_log_level VARCHAR,
    p_service_name VARCHAR,
    p_message TEXT,
    p_context JSONB DEFAULT '{}'::JSONB
) RETURNS UUID AS $$
DECLARE
    v_id UUID;
BEGIN
    INSERT INTO system_logs (log_level, service_name, message, context)
    VALUES (p_log_level, p_service_name, p_message, p_context)
    RETURNING id INTO v_id;
    RETURN v_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Function to increment usage quota
CREATE OR REPLACE FUNCTION increment_usage_quota(
    p_user_id_hash VARCHAR,
    p_service_name VARCHAR,
    p_requests INTEGER DEFAULT 1,
    p_tokens INTEGER DEFAULT 0,
    p_cost DECIMAL DEFAULT 0.00
) RETURNS void AS $$
BEGIN
    INSERT INTO usage_quota (user_id_hash, service_name, requests_count, tokens_used, cost, period_start, period_end)
    VALUES (
        p_user_id_hash,
        p_service_name,
        p_requests,
        p_tokens,
        p_cost,
        DATE_TRUNC('month', NOW()),
        DATE_TRUNC('month', NOW()) + INTERVAL '1 month' - INTERVAL '1 day'
    )
    ON CONFLICT DO UPDATE SET
        requests_count = usage_quota.requests_count + p_requests,
        tokens_used = usage_quota.tokens_used + p_tokens,
        cost = usage_quota.cost + p_cost;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Function to find similar embeddings
CREATE OR REPLACE FUNCTION find_similar_embeddings(
    p_embedding vector,
    p_limit INTEGER DEFAULT 5,
    p_threshold FLOAT DEFAULT 0.7
) RETURNS TABLE(id UUID, content TEXT, similarity FLOAT) AS $$
BEGIN
    RETURN QUERY
    SELECT
        embeddings.id,
        embeddings.content,
        (1 - (embeddings.embedding <=> p_embedding))::FLOAT as similarity
    FROM embeddings
    WHERE (1 - (embeddings.embedding <=> p_embedding)) >= p_threshold
    ORDER BY embeddings.embedding <=> p_embedding
    LIMIT p_limit;
END;
$$ LANGUAGE plpgsql;

-- =============================================================================
-- SEED DATA
-- =============================================================================

-- Insert default feature flags
INSERT INTO feature_flags (flag_name, enabled, rollout_percentage, description)
VALUES
    ('gemini_analysis_enabled', true, 100, 'Enable Gemini API for medical analysis'),
    ('push_notifications_enabled', true, 50, 'Enable push notifications (rollout 50%)'),
    ('offline_mode_enabled', false, 0, 'Enable offline mode feature'),
    ('advanced_analytics_enabled', true, 100, 'Enable advanced analytics dashboard')
ON CONFLICT DO NOTHING;

-- =============================================================================
-- COMMENTS & DOCUMENTATION
-- =============================================================================

COMMENT ON TABLE analytics_events IS 'Anonymized analytics events for research and monitoring';
COMMENT ON TABLE diagnostic_interactions IS 'User interactions with diagnostic tools for model improvement';
COMMENT ON TABLE embeddings IS 'Vector embeddings for semantic search using pgvector';
COMMENT ON TABLE system_logs IS 'System event and error logs';
COMMENT ON TABLE feature_flags IS 'Feature flags for gradual rollouts and A/B testing';
COMMENT ON TABLE usage_quota IS 'API usage tracking for rate limiting and billing';

COMMENT ON COLUMN analytics_events.user_id_hash IS 'SHA-256 hash of user ID for anonymity';
COMMENT ON COLUMN embeddings.embedding IS '768-dimensional vector embedding (Gemini model)';
COMMENT ON COLUMN feature_flags.rollout_percentage IS 'Percentage of users to enable feature for (0-100)';

-- =============================================================================
-- GRANTS FOR RLS POLICIES
-- =============================================================================

-- Grant service_role full access
GRANT ALL ON analytics_events, diagnostic_interactions, embeddings, system_logs, feature_flags, usage_quota TO service_role;

-- Grant anon read on public tables
GRANT SELECT ON embeddings, feature_flags TO anon;
GRANT INSERT ON analytics_events, diagnostic_interactions TO anon;

-- Grant authenticated read on public tables
GRANT SELECT ON embeddings, feature_flags TO authenticated;

-- =============================================================================
-- INITIALIZATION COMPLETE
-- =============================================================================
-- Schema is ready for production use with:
-- ✓ pgvector extension for semantic search
-- ✓ Row Level Security (RLS) configured
-- ✓ Indexes for performance optimization
-- ✓ Stored procedures for common operations
-- ✓ Feature flags for controlled rollouts
-- =============================================================================
