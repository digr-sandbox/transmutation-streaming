BEGIN;
CREATE TABLE IF NOT EXISTS audit_logs (
    request_id UUID PRIMARY KEY,
    user_email TEXT NOT NULL,
    action_type VARCHAR(50) CHECK (action_type IN ('CREATE', 'UPDATE', 'DELETE')),
    metadata JSONB,
    created_at TIMESTAMPTZ DEFAULT NOW()
);
COMMIT;