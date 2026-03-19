-- ============================================================
-- UpliftEdu - Supabase SQL Schema
-- Ed-tech platform: courses, students, leads, placements
-- Chennai, India
-- ============================================================
-- Paste this entire file into Supabase SQL Editor and run.
-- ============================================================

-- Enable UUID generation
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- ============================================================
-- 1. COUNSELORS
-- ============================================================
CREATE TABLE counselors (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name TEXT NOT NULL,
  email TEXT UNIQUE NOT NULL,
  phone TEXT,
  is_active BOOLEAN NOT NULL DEFAULT true,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

ALTER TABLE counselors ENABLE ROW LEVEL SECURITY;

-- Service role full access
CREATE POLICY "Service role full access on counselors"
  ON counselors FOR ALL
  USING (auth.role() = 'service_role')
  WITH CHECK (auth.role() = 'service_role');

-- Authenticated users can read active counselors
CREATE POLICY "Authenticated can read active counselors"
  ON counselors FOR SELECT
  TO authenticated
  USING (is_active = true);

-- ============================================================
-- 2. COURSES
-- ============================================================
CREATE TYPE course_category AS ENUM (
  'coding', 'commerce', 'technical', 'marketing',
  'finance', 'teaching', 'language', 'healthcare', 'others'
);

CREATE TABLE courses (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name TEXT NOT NULL,
  slug TEXT UNIQUE NOT NULL,
  category course_category NOT NULL,
  description TEXT,
  duration_months INTEGER NOT NULL,
  price NUMERIC(10,2) NOT NULL,
  discounted_price NUMERIC(10,2),
  sessions_count INTEGER,
  is_active BOOLEAN NOT NULL DEFAULT true,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_courses_slug ON courses (slug);
CREATE INDEX idx_courses_category ON courses (category);
CREATE INDEX idx_courses_is_active ON courses (is_active);

ALTER TABLE courses ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Service role full access on courses"
  ON courses FOR ALL
  USING (auth.role() = 'service_role')
  WITH CHECK (auth.role() = 'service_role');

-- Anyone can read active courses (public catalogue)
CREATE POLICY "Public can read active courses"
  ON courses FOR SELECT
  TO anon, authenticated
  USING (is_active = true);

-- ============================================================
-- 3. LEADS
-- ============================================================
CREATE TYPE lead_status AS ENUM (
  'new', 'contacted', 'counselled', 'converted', 'lost'
);

CREATE TABLE leads (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name TEXT NOT NULL,
  phone TEXT NOT NULL,
  email TEXT,
  course_interest UUID REFERENCES courses(id) ON DELETE SET NULL,
  source TEXT,           -- utm_source
  medium TEXT,           -- utm_medium
  campaign TEXT,         -- utm_campaign
  status lead_status NOT NULL DEFAULT 'new',
  assigned_counselor UUID REFERENCES counselors(id) ON DELETE SET NULL,
  notes TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_leads_status ON leads (status);
CREATE INDEX idx_leads_course_interest ON leads (course_interest);
CREATE INDEX idx_leads_assigned_counselor ON leads (assigned_counselor);
CREATE INDEX idx_leads_created_at ON leads (created_at DESC);
CREATE INDEX idx_leads_source ON leads (source);

ALTER TABLE leads ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Service role full access on leads"
  ON leads FOR ALL
  USING (auth.role() = 'service_role')
  WITH CHECK (auth.role() = 'service_role');

-- Public (website form) can insert leads
CREATE POLICY "Public can insert leads"
  ON leads FOR INSERT
  TO anon
  WITH CHECK (true);

-- Auto-update updated_at
CREATE OR REPLACE FUNCTION update_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_leads_updated_at
  BEFORE UPDATE ON leads
  FOR EACH ROW
  EXECUTE FUNCTION update_updated_at();

-- ============================================================
-- 4. BATCHES
-- ============================================================
CREATE TYPE batch_status AS ENUM ('upcoming', 'active', 'completed');

CREATE TABLE batches (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  course_id UUID NOT NULL REFERENCES courses(id) ON DELETE CASCADE,
  batch_code TEXT UNIQUE NOT NULL,         -- e.g. FSD-8
  start_date DATE NOT NULL,
  end_date DATE,
  mentor_name TEXT,
  mentor_email TEXT,
  capacity INTEGER NOT NULL DEFAULT 30,
  enrolled_count INTEGER NOT NULL DEFAULT 0,
  status batch_status NOT NULL DEFAULT 'upcoming',
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_batches_course_id ON batches (course_id);
CREATE INDEX idx_batches_status ON batches (status);
CREATE INDEX idx_batches_start_date ON batches (start_date);

ALTER TABLE batches ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Service role full access on batches"
  ON batches FOR ALL
  USING (auth.role() = 'service_role')
  WITH CHECK (auth.role() = 'service_role');

CREATE POLICY "Authenticated can read batches"
  ON batches FOR SELECT
  TO authenticated
  USING (true);

-- ============================================================
-- 5. STUDENTS
-- ============================================================
CREATE TYPE payment_status AS ENUM ('pending', 'partial', 'paid');
CREATE TYPE payment_plan  AS ENUM ('full', 'emi');
CREATE TYPE student_status AS ENUM ('active', 'completed', 'dropped');

CREATE TABLE students (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  auth_user_id UUID UNIQUE REFERENCES auth.users(id) ON DELETE SET NULL,
  name TEXT NOT NULL,
  email TEXT NOT NULL,
  phone TEXT NOT NULL,
  course_id UUID NOT NULL REFERENCES courses(id) ON DELETE RESTRICT,
  batch_id UUID REFERENCES batches(id) ON DELETE SET NULL,
  enrollment_date DATE NOT NULL DEFAULT CURRENT_DATE,
  payment_status payment_status NOT NULL DEFAULT 'pending',
  payment_plan payment_plan NOT NULL DEFAULT 'full',
  total_amount NUMERIC(10,2) NOT NULL DEFAULT 0,
  paid_amount NUMERIC(10,2) NOT NULL DEFAULT 0,
  status student_status NOT NULL DEFAULT 'active',
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_students_auth_user_id ON students (auth_user_id);
CREATE INDEX idx_students_course_id ON students (course_id);
CREATE INDEX idx_students_batch_id ON students (batch_id);
CREATE INDEX idx_students_status ON students (status);
CREATE INDEX idx_students_email ON students (email);

ALTER TABLE students ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Service role full access on students"
  ON students FOR ALL
  USING (auth.role() = 'service_role')
  WITH CHECK (auth.role() = 'service_role');

-- Students can read their own record
CREATE POLICY "Students can read own record"
  ON students FOR SELECT
  TO authenticated
  USING (auth.uid() = auth_user_id);

-- ============================================================
-- 6. PAYMENTS
-- ============================================================
CREATE TYPE payment_txn_status AS ENUM ('created', 'captured', 'failed', 'refunded');

CREATE TABLE payments (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  student_id UUID NOT NULL REFERENCES students(id) ON DELETE CASCADE,
  amount NUMERIC(10,2) NOT NULL,
  payment_method TEXT,                     -- upi / card / netbanking / cash
  razorpay_payment_id TEXT,
  razorpay_order_id TEXT,
  status payment_txn_status NOT NULL DEFAULT 'created',
  emi_number INTEGER,                      -- null for full payments
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_payments_student_id ON payments (student_id);
CREATE INDEX idx_payments_status ON payments (status);
CREATE INDEX idx_payments_razorpay_payment_id ON payments (razorpay_payment_id);
CREATE INDEX idx_payments_created_at ON payments (created_at DESC);

ALTER TABLE payments ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Service role full access on payments"
  ON payments FOR ALL
  USING (auth.role() = 'service_role')
  WITH CHECK (auth.role() = 'service_role');

-- Students can read their own payments
CREATE POLICY "Students can read own payments"
  ON payments FOR SELECT
  TO authenticated
  USING (
    student_id IN (
      SELECT id FROM students WHERE auth_user_id = auth.uid()
    )
  );

-- ============================================================
-- 7. ATTENDANCE
-- ============================================================
CREATE TABLE attendance (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  student_id UUID NOT NULL REFERENCES students(id) ON DELETE CASCADE,
  batch_id UUID NOT NULL REFERENCES batches(id) ON DELETE CASCADE,
  session_date DATE NOT NULL,
  session_topic TEXT,
  is_present BOOLEAN NOT NULL DEFAULT false,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (student_id, batch_id, session_date)
);

CREATE INDEX idx_attendance_student_id ON attendance (student_id);
CREATE INDEX idx_attendance_batch_id ON attendance (batch_id);
CREATE INDEX idx_attendance_session_date ON attendance (session_date);

ALTER TABLE attendance ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Service role full access on attendance"
  ON attendance FOR ALL
  USING (auth.role() = 'service_role')
  WITH CHECK (auth.role() = 'service_role');

CREATE POLICY "Students can read own attendance"
  ON attendance FOR SELECT
  TO authenticated
  USING (
    student_id IN (
      SELECT id FROM students WHERE auth_user_id = auth.uid()
    )
  );

-- ============================================================
-- 8. ASSIGNMENTS
-- ============================================================
CREATE TABLE assignments (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  student_id UUID NOT NULL REFERENCES students(id) ON DELETE CASCADE,
  batch_id UUID NOT NULL REFERENCES batches(id) ON DELETE CASCADE,
  title TEXT NOT NULL,
  submitted_at TIMESTAMPTZ,
  score NUMERIC(5,2),                      -- e.g. 95.50 out of 100
  is_on_time BOOLEAN,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_assignments_student_id ON assignments (student_id);
CREATE INDEX idx_assignments_batch_id ON assignments (batch_id);

ALTER TABLE assignments ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Service role full access on assignments"
  ON assignments FOR ALL
  USING (auth.role() = 'service_role')
  WITH CHECK (auth.role() = 'service_role');

CREATE POLICY "Students can read own assignments"
  ON assignments FOR SELECT
  TO authenticated
  USING (
    student_id IN (
      SELECT id FROM students WHERE auth_user_id = auth.uid()
    )
  );

-- ============================================================
-- 9. PLACEMENTS
-- ============================================================
CREATE TYPE placement_status AS ENUM ('applied', 'interviewed', 'offered', 'joined');

CREATE TABLE placements (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  student_id UUID NOT NULL REFERENCES students(id) ON DELETE CASCADE,
  company TEXT NOT NULL,
  role TEXT NOT NULL,
  salary_lpa NUMERIC(5,2),                 -- e.g. 4.50 LPA
  offer_date DATE,
  join_date DATE,
  status placement_status NOT NULL DEFAULT 'applied',
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_placements_student_id ON placements (student_id);
CREATE INDEX idx_placements_status ON placements (status);
CREATE INDEX idx_placements_company ON placements (company);

ALTER TABLE placements ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Service role full access on placements"
  ON placements FOR ALL
  USING (auth.role() = 'service_role')
  WITH CHECK (auth.role() = 'service_role');

CREATE POLICY "Students can read own placements"
  ON placements FOR SELECT
  TO authenticated
  USING (
    student_id IN (
      SELECT id FROM students WHERE auth_user_id = auth.uid()
    )
  );

-- ============================================================
-- 10. SUPPORT TICKETS
-- ============================================================
CREATE TYPE ticket_priority AS ENUM ('low', 'medium', 'high', 'urgent');
CREATE TYPE ticket_status   AS ENUM ('open', 'in_progress', 'resolved', 'closed');

CREATE TABLE support_tickets (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  student_id UUID NOT NULL REFERENCES students(id) ON DELETE CASCADE,
  subject TEXT NOT NULL,
  description TEXT,
  priority ticket_priority NOT NULL DEFAULT 'medium',
  status ticket_status NOT NULL DEFAULT 'open',
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  resolved_at TIMESTAMPTZ
);

CREATE INDEX idx_support_tickets_student_id ON support_tickets (student_id);
CREATE INDEX idx_support_tickets_status ON support_tickets (status);
CREATE INDEX idx_support_tickets_priority ON support_tickets (priority);
CREATE INDEX idx_support_tickets_created_at ON support_tickets (created_at DESC);

ALTER TABLE support_tickets ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Service role full access on support_tickets"
  ON support_tickets FOR ALL
  USING (auth.role() = 'service_role')
  WITH CHECK (auth.role() = 'service_role');

-- Students can read and create their own tickets
CREATE POLICY "Students can read own tickets"
  ON support_tickets FOR SELECT
  TO authenticated
  USING (
    student_id IN (
      SELECT id FROM students WHERE auth_user_id = auth.uid()
    )
  );

CREATE POLICY "Students can create own tickets"
  ON support_tickets FOR INSERT
  TO authenticated
  WITH CHECK (
    student_id IN (
      SELECT id FROM students WHERE auth_user_id = auth.uid()
    )
  );

-- ============================================================
-- SEED DATA: Counselors
-- ============================================================
INSERT INTO counselors (name, email, phone) VALUES
  ('Priya S.', 'priya@upliftedu.in', '9380058581'),
  ('Arun M.', 'arun@upliftedu.in', '9380058582'),
  ('Deepa R.', 'deepa@upliftedu.in', '9380058583');

-- ============================================================
-- SEED DATA: 38 Courses
-- ============================================================
INSERT INTO courses (name, slug, category, duration_months, price, discounted_price, sessions_count, description) VALUES
  -- CODING (10)
  ('Full Stack Development',     'full-stack-development',     'coding',     7,  30000, NULL, 120, 'Master front-end and back-end web development with React, Node.js, databases, and deployment.'),
  ('Data Science',               'data-science',               'coding',     6,  30000, NULL, 100, 'Learn Python, statistics, machine learning, and data visualization for real-world analytics.'),
  ('Software Testing',           'software-testing',           'coding',     6,  25000, NULL,  90, 'Manual and automation testing with Selenium, API testing, and CI/CD pipelines.'),
  ('Python Programming',         'python-programming',         'coding',     4,  20000, NULL,  60, 'From basics to advanced Python including OOP, file handling, and project work.'),
  ('UI/UX Design',               'ui-ux-design',               'coding',     5,  25000, NULL,  80, 'User research, wireframing, prototyping with Figma, and design systems.'),
  ('Data Analytics',             'data-analytics',             'coding',     5,  25000, NULL,  80, 'Excel, SQL, Power BI, Tableau, and Python for business intelligence.'),
  ('AI Tools Mastery',           'ai-tools-mastery',           'coding',     3,  20000, NULL,  45, 'Hands-on with ChatGPT, Midjourney, Copilot, and automation workflows.'),
  ('AI Powered Cybersecurity',   'ai-powered-cybersecurity',   'coding',     6,  30000, NULL, 100, 'Network security, ethical hacking, SIEM tools, and AI-driven threat detection.'),
  ('Architecting on AWS',        'architecting-on-aws',        'coding',     4,  30000, NULL,  60, 'AWS Solutions Architect prep: EC2, S3, Lambda, VPC, and cloud best practices.'),

  -- COMMERCE (10)
  ('Practical Accounting',       'practical-accounting',       'commerce',   4,  20000, NULL,  60, 'GST, TDS, payroll, balance sheets, and Tally for job-ready accounting skills.'),
  ('SAP FICO',                   'sap-fico',                   'commerce',   3,  25000, NULL,  50, 'SAP Financial Accounting and Controlling module with real-time project work.'),
  ('SAP MM',                     'sap-mm',                     'commerce',   3,  25000, NULL,  50, 'SAP Materials Management: procurement, inventory, and invoice verification.'),
  ('SAP SD',                     'sap-sd',                     'commerce',   3,  25000, NULL,  50, 'SAP Sales & Distribution: order management, pricing, billing, and shipping.'),
  ('ACCA',                       'acca',                       'commerce',  12,  45000, NULL, 200, 'Association of Chartered Certified Accountants - globally recognised qualification.'),
  ('HR Management',              'hr-management',              'commerce',   4,  20000, NULL,  60, 'Recruitment, payroll, compliance, performance management, and HR analytics.'),
  ('PwC Edge',                   'pwc-edge',                   'commerce',   3,  25000, NULL,  50, 'Industry-aligned program covering audit, tax, and consulting fundamentals.'),
  ('Enrolled Agent',             'enrolled-agent',             'commerce',   6,  35000, NULL,  90, 'US tax certification: IRS representation, individual and business taxation.'),
  ('CMA USA',                    'cma-usa',                    'commerce',  12,  50000, NULL, 200, 'Certified Management Accountant - financial planning, analysis, and control.'),
  ('Certified Tax Professional', 'certified-tax-professional', 'commerce',   4,  20000, NULL,  60, 'Indian taxation: income tax, GST, TDS filing, and tax planning.'),
  ('Tally Prime',                'tally-prime',                'commerce',   2,  10000, NULL,  30, 'Complete Tally Prime with GST, voucher entry, inventory, and payroll.'),

  -- TECHNICAL (6)
  ('Quantity Survey',            'quantity-survey',            'technical',  4,  25000, NULL,  60, 'Cost estimation, measurement, and billing for construction projects.'),
  ('MEP',                        'mep',                        'technical',  4,  25000, NULL,  60, 'Mechanical, Electrical, and Plumbing design for buildings and infrastructure.'),
  ('Robotics & AI',              'robotics-and-ai',            'technical',  6,  30000, NULL, 100, 'Arduino, sensors, actuators, computer vision, and robotic arm programming.'),
  ('Structural Design',          'structural-design',          'technical',  4,  25000, NULL,  60, 'STAAD Pro, ETABS, structural analysis, and RCC/steel design.'),
  ('BIM',                        'bim',                        'technical',  4,  25000, NULL,  60, 'Building Information Modeling with Revit for architecture and construction.'),
  ('Embedded System',            'embedded-system',            'technical',  5,  25000, NULL,  80, 'Microcontrollers, RTOS, C/C++, PCB design, and IoT applications.'),

  -- MARKETING (2)
  ('Digital Marketing',          'digital-marketing',          'marketing',  6,  25000, NULL,  90, 'SEO, SEM, social media, content marketing, email marketing, and analytics.'),
  ('Performance Marketing',      'performance-marketing',      'marketing',  4,  20000, NULL,  60, 'Google Ads, Meta Ads, campaign optimization, ROAS, and attribution models.'),

  -- FINANCE (3)
  ('Stock Market',               'stock-market',               'finance',    3,  15000, NULL,  45, 'Technical analysis, fundamental analysis, options, and trading strategies.'),
  ('Forex Trading',              'forex-trading',              'finance',    3,  15000, NULL,  45, 'Currency pairs, chart patterns, risk management, and live trading practice.'),
  ('Mutual Funds',               'mutual-funds',               'finance',    2,  12000, NULL,  30, 'SIP, SWP, fund selection, portfolio building, and AMFI certification prep.'),

  -- TEACHING (1)
  ('B.Ed Coaching',              'bed-coaching',               'teaching',  12,  35000, NULL, 200, 'Comprehensive B.Ed entrance coaching with pedagogy, subject knowledge, and mock tests.'),

  -- LANGUAGE (4)
  ('Spoken English',             'spoken-english',             'language',   3,  10000, NULL,  45, 'Grammar, pronunciation, vocabulary, and fluency for everyday and professional use.'),
  ('German Language',            'german-language',            'language',   6,  20000, NULL,  90, 'A1 to B1 level German: grammar, conversation, reading, and writing.'),
  ('PTE',                        'pte',                        'language',   2,  15000, NULL,  30, 'Pearson Test of English preparation with mock tests and score-boosting strategies.'),
  ('IELTS',                      'ielts',                      'language',   2,  15000, NULL,  30, 'IELTS Academic & General: listening, reading, writing, and speaking prep.'),

  -- HEALTHCARE (1)
  ('Hospital Administration',    'hospital-administration',    'healthcare', 6,  25000, NULL,  90, 'Hospital operations, medical records, health informatics, and quality management.'),

  -- OTHERS (1)
  ('Fashion Designing',          'fashion-designing',          'others',     6,  25000, NULL,  90, 'Sketching, pattern making, draping, textile science, and portfolio building.');

-- ============================================================
-- HELPFUL VIEWS (optional but useful for admin dashboards)
-- ============================================================

-- Lead funnel summary
CREATE OR REPLACE VIEW v_lead_funnel AS
SELECT
  status,
  COUNT(*) AS lead_count,
  ROUND(COUNT(*) * 100.0 / NULLIF(SUM(COUNT(*)) OVER (), 0), 1) AS pct
FROM leads
GROUP BY status
ORDER BY
  CASE status
    WHEN 'new' THEN 1
    WHEN 'contacted' THEN 2
    WHEN 'counselled' THEN 3
    WHEN 'converted' THEN 4
    WHEN 'lost' THEN 5
  END;

-- Student payment summary
CREATE OR REPLACE VIEW v_payment_summary AS
SELECT
  s.id AS student_id,
  s.name,
  c.name AS course_name,
  s.total_amount,
  s.paid_amount,
  s.total_amount - s.paid_amount AS balance,
  s.payment_status,
  s.payment_plan
FROM students s
JOIN courses c ON c.id = s.course_id;

-- Batch occupancy
CREATE OR REPLACE VIEW v_batch_occupancy AS
SELECT
  b.id AS batch_id,
  b.batch_code,
  c.name AS course_name,
  b.mentor_name,
  b.capacity,
  b.enrolled_count,
  b.capacity - b.enrolled_count AS seats_available,
  b.status,
  b.start_date,
  b.end_date
FROM batches b
JOIN courses c ON c.id = b.course_id;

-- Placement stats
CREATE OR REPLACE VIEW v_placement_stats AS
SELECT
  c.name AS course_name,
  COUNT(p.id) AS total_placements,
  COUNT(p.id) FILTER (WHERE p.status = 'joined') AS joined_count,
  ROUND(AVG(p.salary_lpa) FILTER (WHERE p.status = 'joined'), 2) AS avg_salary_lpa,
  MAX(p.salary_lpa) FILTER (WHERE p.status = 'joined') AS max_salary_lpa
FROM placements p
JOIN students s ON s.id = p.student_id
JOIN courses c ON c.id = s.course_id
GROUP BY c.name;

-- ============================================================
-- DONE
-- ============================================================
