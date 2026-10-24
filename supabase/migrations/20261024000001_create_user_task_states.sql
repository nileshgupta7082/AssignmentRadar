-- ==============================================================================
-- Migration: 20261024000001_create_user_task_states.sql
-- Project: Assignment Radar
-- Description: Creates the user_task_states table for cloud-synchronized personal
--              task completion status, archive state, notes, and priority overrides.
-- ==============================================================================

-- 1. Enable UUID extension if not already present
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- 2. Create the user_task_states table
CREATE TABLE IF NOT EXISTS public.user_task_states (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    task_key TEXT NOT NULL,
    source TEXT NOT NULL DEFAULT 'moodle',
    source_account_key TEXT,
    is_completed BOOLEAN NOT NULL DEFAULT FALSE,
    is_archived BOOLEAN NOT NULL DEFAULT FALSE,
    priority_override TEXT,
    notes TEXT,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now()),
    version BIGINT NOT NULL DEFAULT 1,

    -- Unique constraint: A user has exactly one state record per unique task_key
    CONSTRAINT user_task_states_user_task_unique UNIQUE (user_id, task_key)
);

-- 3. Create high-performance indexes for query optimization
CREATE INDEX IF NOT EXISTS idx_user_task_states_user_key 
    ON public.user_task_states(user_id, task_key);

CREATE INDEX IF NOT EXISTS idx_user_task_states_user_account 
    ON public.user_task_states(user_id, source_account_key);

CREATE INDEX IF NOT EXISTS idx_user_task_states_updated_at 
    ON public.user_task_states(updated_at DESC);

-- 4. Enable Row Level Security (RLS) for absolute tenant isolation
ALTER TABLE public.user_task_states ENABLE ROW LEVEL SECURITY;

-- Drop existing policies if re-running
DROP POLICY IF EXISTS "Users can view their own task states" ON public.user_task_states;
DROP POLICY IF EXISTS "Users can insert their own task states" ON public.user_task_states;
DROP POLICY IF EXISTS "Users can update their own task states" ON public.user_task_states;
DROP POLICY IF EXISTS "Users can delete their own task states" ON public.user_task_states;

-- Policy: Select - Authenticated users can view ONLY their own task states
CREATE POLICY "Users can view their own task states"
    ON public.user_task_states
    FOR SELECT
    TO authenticated
    USING (auth.uid() = user_id);

-- Policy: Insert - Authenticated users can insert ONLY for their own user_id
CREATE POLICY "Users can insert their own task states"
    ON public.user_task_states
    FOR INSERT
    TO authenticated
    WITH CHECK (auth.uid() = user_id);

-- Policy: Update - Authenticated users can update ONLY their own task states
CREATE POLICY "Users can update their own task states"
    ON public.user_task_states
    FOR UPDATE
    TO authenticated
    USING (auth.uid() = user_id)
    WITH CHECK (auth.uid() = user_id);

-- Policy: Delete - Authenticated users can delete ONLY their own task states
CREATE POLICY "Users can delete their own task states"
    ON public.user_task_states
    FOR DELETE
    TO authenticated
    USING (auth.uid() = user_id);

-- 5. Automatic trigger for updating updated_at and incrementing version
CREATE OR REPLACE FUNCTION public.handle_user_task_states_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = timezone('utc'::text, now());
    NEW.version = OLD.version + 1;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS tr_user_task_states_updated_at ON public.user_task_states;
CREATE TRIGGER tr_user_task_states_updated_at
    BEFORE UPDATE ON public.user_task_states
    FOR EACH ROW
    EXECUTE FUNCTION public.handle_user_task_states_updated_at();

-- 6. Add table documentation comment
COMMENT ON TABLE public.user_task_states IS 'Persistent student task states (completion, archive, notes) synchronized with Assignment Radar iOS app.';
COMMENT ON COLUMN public.user_task_states.task_key IS 'Stable unique task identifier (e.g. moodle_<eventId> or local_<uuid>).';
COMMENT ON COLUMN public.user_task_states.source_account_key IS 'Normalized student identifier linking Moodle LMS account to this personal task state.';
