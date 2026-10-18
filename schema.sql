-- 駱駝教師生涯導航：PostgreSQL 初始資料庫結構
-- 建議 PostgreSQL 15+。此檔建立 schema，不會建立實際使用者帳號或密碼。
-- 請先在測試資料庫執行，正式部署前完成資安、法務與資料治理審查。

BEGIN;

CREATE EXTENSION IF NOT EXISTS pgcrypto;

CREATE TYPE app_role AS ENUM ('teacher', 'admin');
CREATE TYPE model_status AS ENUM ('draft', 'published', 'archived');
CREATE TYPE plan_mode AS ENUM ('current_review', 'target_development', 'combined');
CREATE TYPE record_status AS ENUM ('draft', 'in_progress', 'submitted', 'completed', 'paused', 'cancelled');
CREATE TYPE task_status AS ENUM ('todo', 'in_progress', 'done', 'skipped');

CREATE TABLE users (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    email TEXT NOT NULL UNIQUE,
    display_name TEXT NOT NULL,
    auth_provider TEXT NOT NULL DEFAULT 'external',
    provider_subject TEXT,
    account_status TEXT NOT NULL DEFAULT 'active'
        CHECK (account_status IN ('active', 'disabled', 'pending')),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    CHECK (length(trim(email)) > 3)
);

CREATE UNIQUE INDEX users_provider_subject_uq
    ON users(auth_provider, provider_subject)
    WHERE provider_subject IS NOT NULL;

CREATE TABLE user_roles (
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    role app_role NOT NULL,
    granted_by UUID REFERENCES users(id),
    granted_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (user_id, role)
);

CREATE TABLE positions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    code TEXT NOT NULL UNIQUE,
    name TEXT NOT NULL UNIQUE,
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    sort_order INTEGER NOT NULL DEFAULT 0,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

INSERT INTO positions(code, name, sort_order) VALUES
('admin', '行政', 1),
('homeroom', '導師', 2),
('subject', '科任教師', 3)
ON CONFLICT (code) DO NOTHING;

CREATE TABLE teacher_profiles (
    user_id UUID PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
    current_position_id UUID REFERENCES positions(id),
    salary_grade TEXT,
    weekly_available_minutes INTEGER CHECK (weekly_available_minutes IS NULL OR weekly_available_minutes >= 0),
    profile_completed_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
COMMENT ON COLUMN teacher_profiles.salary_grade IS
'僅記錄薪級／薪點級別代碼，不記錄實際薪資金額。';

-- 能力為跨職位共用的穩定主檔；版本化內容另存於 competency_versions。
CREATE TABLE competencies (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    code TEXT NOT NULL UNIQUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    retired_at TIMESTAMPTZ
);

CREATE TABLE competency_versions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    competency_id UUID NOT NULL REFERENCES competencies(id),
    version_no INTEGER NOT NULL CHECK (version_no > 0),
    name TEXT NOT NULL,
    definition TEXT NOT NULL,
    status model_status NOT NULL DEFAULT 'draft',
    created_by UUID REFERENCES users(id),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (competency_id, version_no)
);

CREATE TABLE position_model_versions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    position_id UUID NOT NULL REFERENCES positions(id),
    version_no INTEGER NOT NULL CHECK (version_no > 0),
    status model_status NOT NULL DEFAULT 'draft',
    change_summary TEXT,
    created_by UUID REFERENCES users(id),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    published_by UUID REFERENCES users(id),
    published_at TIMESTAMPTZ,
    UNIQUE (position_id, version_no),
    CHECK (
      (status = 'published' AND published_at IS NOT NULL)
      OR status <> 'published'
    )
);

-- 每個職位模型版本可引用共用能力，但保有獨立目標等級、權重與排序。
CREATE TABLE position_model_competencies (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    position_model_version_id UUID NOT NULL REFERENCES position_model_versions(id),
    competency_version_id UUID NOT NULL REFERENCES competency_versions(id),
    target_level NUMERIC(3,2) NOT NULL CHECK (target_level BETWEEN 1 AND 5),
    weight NUMERIC(8,3) NOT NULL DEFAULT 1 CHECK (weight > 0),
    is_applicable BOOLEAN NOT NULL DEFAULT TRUE,
    sort_order INTEGER NOT NULL DEFAULT 0,
    UNIQUE (position_model_version_id, competency_version_id)
);

CREATE TABLE competency_domains (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    position_model_version_id UUID NOT NULL REFERENCES position_model_versions(id),
    name TEXT NOT NULL,
    description TEXT,
    sort_order INTEGER NOT NULL DEFAULT 0,
    UNIQUE (position_model_version_id, name)
);

CREATE TABLE competency_domain_members (
    competency_domain_id UUID NOT NULL REFERENCES competency_domains(id) ON DELETE CASCADE,
    position_model_competency_id UUID NOT NULL REFERENCES position_model_competencies(id) ON DELETE CASCADE,
    PRIMARY KEY (competency_domain_id, position_model_competency_id)
);

CREATE TABLE competency_indicators (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    competency_version_id UUID NOT NULL REFERENCES competency_versions(id),
    indicator_text TEXT NOT NULL,
    sort_order INTEGER NOT NULL DEFAULT 0,
    is_required BOOLEAN NOT NULL DEFAULT TRUE
);

CREATE TABLE rating_scale_versions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    version_no INTEGER NOT NULL UNIQUE CHECK (version_no > 0),
    name TEXT NOT NULL,
    status model_status NOT NULL DEFAULT 'draft',
    created_by UUID REFERENCES users(id),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    published_at TIMESTAMPTZ
);

CREATE TABLE rating_scale_levels (
    rating_scale_version_id UUID NOT NULL REFERENCES rating_scale_versions(id),
    level SMALLINT NOT NULL CHECK (level BETWEEN 1 AND 5),
    label TEXT NOT NULL,
    description TEXT NOT NULL,
    PRIMARY KEY (rating_scale_version_id, level)
);

CREATE TABLE assessment_rule_versions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    version_no INTEGER NOT NULL UNIQUE CHECK (version_no > 0),
    rule_definition JSONB NOT NULL,
    status model_status NOT NULL DEFAULT 'draft',
    created_by UUID REFERENCES users(id),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    published_at TIMESTAMPTZ
);

CREATE TABLE assessment_items (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    competency_version_id UUID NOT NULL REFERENCES competency_versions(id),
    item_code TEXT NOT NULL,
    prompt TEXT NOT NULL,
    help_text TEXT,
    item_weight NUMERIC(8,3) NOT NULL DEFAULT 1 CHECK (item_weight > 0),
    sort_order INTEGER NOT NULL DEFAULT 0,
    is_required BOOLEAN NOT NULL DEFAULT TRUE,
    UNIQUE (competency_version_id, item_code)
);

CREATE TABLE assessment_item_scale_descriptions (
    assessment_item_id UUID NOT NULL REFERENCES assessment_items(id) ON DELETE CASCADE,
    level SMALLINT NOT NULL CHECK (level BETWEEN 1 AND 5),
    description TEXT NOT NULL,
    PRIMARY KEY (assessment_item_id, level)
);

CREATE TABLE development_plans (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES users(id),
    mode plan_mode NOT NULL,
    current_position_id UUID REFERENCES positions(id),
    target_position_id UUID REFERENCES positions(id),
    reason TEXT,
    status record_status NOT NULL DEFAULT 'in_progress',
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    CHECK (mode <> 'current_review' OR current_position_id IS NOT NULL),
    CHECK (mode <> 'target_development' OR target_position_id IS NOT NULL),
    CHECK (mode <> 'combined' OR (current_position_id IS NOT NULL AND target_position_id IS NOT NULL))
);

CREATE TABLE assessments (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    plan_id UUID NOT NULL REFERENCES development_plans(id),
    position_model_version_id UUID NOT NULL REFERENCES position_model_versions(id),
    rating_scale_version_id UUID NOT NULL REFERENCES rating_scale_versions(id),
    assessment_rule_version_id UUID NOT NULL REFERENCES assessment_rule_versions(id),
    assessment_type TEXT NOT NULL CHECK (assessment_type IN ('current_review', 'target_development')),
    status record_status NOT NULL DEFAULT 'in_progress',
    -- 快照欄位用於保留當時題目與量尺，避免模型更新影響歷史結果。
    model_snapshot JSONB NOT NULL DEFAULT '{}'::jsonb,
    started_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    submitted_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    CHECK ((status <> 'submitted') OR submitted_at IS NOT NULL)
);

CREATE TABLE assessment_responses (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    assessment_id UUID NOT NULL REFERENCES assessments(id) ON DELETE CASCADE,
    assessment_item_id UUID NOT NULL REFERENCES assessment_items(id),
    prompt_snapshot TEXT NOT NULL,
    rating SMALLINT CHECK (rating BETWEEN 1 AND 5),
    comment TEXT,
    answered_at TIMESTAMPTZ,
    UNIQUE (assessment_id, assessment_item_id)
);

CREATE TABLE competency_results (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    assessment_id UUID NOT NULL REFERENCES assessments(id) ON DELETE CASCADE,
    competency_version_id UUID NOT NULL REFERENCES competency_versions(id),
    competency_name_snapshot TEXT NOT NULL,
    score NUMERIC(5,2) NOT NULL CHECK (score BETWEEN 1 AND 5),
    target_level NUMERIC(3,2) NOT NULL CHECK (target_level BETWEEN 1 AND 5),
    gap NUMERIC(5,2) NOT NULL CHECK (gap >= 0),
    signed_gap NUMERIC(5,2) NOT NULL,
    competency_weight NUMERIC(8,3) NOT NULL DEFAULT 1 CHECK (competency_weight > 0),
    calculated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (assessment_id, competency_version_id)
);

CREATE TABLE action_templates (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    competency_version_id UUID REFERENCES competency_versions(id),
    title TEXT NOT NULL,
    description TEXT NOT NULL,
    steps JSONB NOT NULL DEFAULT '[]'::jsonb,
    evidence_guidance TEXT,
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    created_by UUID REFERENCES users(id),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE plan_action_cards (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    plan_id UUID NOT NULL REFERENCES development_plans(id) ON DELETE CASCADE,
    competency_result_id UUID REFERENCES competency_results(id),
    template_id UUID REFERENCES action_templates(id),
    title_snapshot TEXT NOT NULL,
    description_snapshot TEXT NOT NULL,
    priority_order INTEGER NOT NULL DEFAULT 1,
    status task_status NOT NULL DEFAULT 'todo',
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE weekly_tasks (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    action_card_id UUID REFERENCES plan_action_cards(id) ON DELETE CASCADE,
    plan_id UUID NOT NULL REFERENCES development_plans(id) ON DELETE CASCADE,
    week_start_date DATE NOT NULL,
    title TEXT NOT NULL,
    description TEXT,
    status task_status NOT NULL DEFAULT 'todo',
    due_date DATE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    CHECK (due_date IS NULL OR due_date >= week_start_date)
);

CREATE TABLE weekly_task_logs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    weekly_task_id UUID NOT NULL REFERENCES weekly_tasks(id) ON DELETE CASCADE,
    logged_by UUID NOT NULL REFERENCES users(id),
    logged_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    progress_note TEXT,
    evidence_url TEXT
);

CREATE TABLE weekly_reviews (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    plan_id UUID NOT NULL REFERENCES development_plans(id) ON DELETE CASCADE,
    week_start_date DATE NOT NULL,
    reflection TEXT,
    completion_rate NUMERIC(5,2) CHECK (completion_rate BETWEEN 0 AND 100),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (plan_id, week_start_date)
);

CREATE TABLE audit_logs (
    id BIGSERIAL PRIMARY KEY,
    actor_user_id UUID REFERENCES users(id),
    action TEXT NOT NULL,
    entity_type TEXT NOT NULL,
    entity_id TEXT,
    metadata JSONB NOT NULL DEFAULT '{}'::jsonb,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE model_change_logs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    position_model_version_id UUID REFERENCES position_model_versions(id),
    actor_user_id UUID REFERENCES users(id),
    change_summary TEXT NOT NULL,
    before_snapshot JSONB,
    after_snapshot JSONB,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX assessments_plan_idx ON assessments(plan_id, created_at DESC);
CREATE INDEX assessment_responses_assessment_idx ON assessment_responses(assessment_id);
CREATE INDEX competency_results_assessment_idx ON competency_results(assessment_id);
CREATE INDEX weekly_tasks_plan_week_idx ON weekly_tasks(plan_id, week_start_date);
CREATE INDEX audit_logs_entity_idx ON audit_logs(entity_type, entity_id, created_at DESC);

-- 安全提醒：
-- 1. 請由後端服務驗證登入身份、角色及資料擁有權。
-- 2. 不要將管理員或資料庫憑證寫入 HTML/前端 JavaScript。
-- 3. 管理員預設只能查看去識別化彙整統計，不應取得個別教師自評明細。
-- 4. 正式版應以資料庫 RLS 或等效後端授權規則限制教師只讀寫自己的資料。
-- 5. published 模型應以 trigger/後端交易保護不可直接修改；修改時建立新版本。
-- 6. 統計報表需設小樣本抑制門檻，降低重新識別風險。

COMMIT;
