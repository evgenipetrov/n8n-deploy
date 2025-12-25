-- n8n Execution History Performance Indexes
-- These indexes optimize queries on the execution_entity table for faster execution history loading.
-- This script runs automatically on first PostgreSQL initialization.
-- For existing deployments, run manually: docker exec -i postgres psql -U $POSTGRES_USER -d $POSTGRES_DB < postgres/init/01-create-indexes.sql

-- Index for workflow-specific execution queries
-- Speeds up: "Show all executions for workflow X"
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_execution_entity_workflow_id
ON execution_entity (workflowId);

-- Index for time-based filtering and sorting
-- Speeds up: "Show executions from last N hours" and default sort by start time
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_execution_entity_started_at
ON execution_entity (startedAt);

-- Index for status-based filtering
-- Speeds up: "Show all failed/running/waiting executions"
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_execution_entity_status
ON execution_entity (status);

-- Index for completion state queries
-- Speeds up: "Show all completed/incomplete executions"
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_execution_entity_finished
ON execution_entity (finished);

-- Composite index for the most common query pattern
-- Speeds up: "Show executions for workflow X ordered by most recent"
-- This is the primary index for execution history page loading
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_execution_entity_workflow_started
ON execution_entity (workflowId, startedAt DESC);

-- Composite index for status filtering within a workflow
-- Speeds up: "Show failed executions for workflow X"
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_execution_entity_workflow_status
ON execution_entity (workflowId, status);
