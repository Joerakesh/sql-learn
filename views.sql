-- 02_views_demo.sql  (run after 01_create_and_load.sql)
USE ds_dept;

/* ---------------------------------------------------------------
   PART 1 - The basics: one view per background
---------------------------------------------------------------- */
CREATE OR REPLACE VIEW v_cs_background AS
SELECT student_id, reg_no, first_name, last_name, ug_degree, ug_percentage, admission_year
FROM   students
WHERE  ug_degree IN ('BCA', 'BSc Computer Science');

CREATE OR REPLACE VIEW v_math_background AS
SELECT student_id, reg_no, first_name, last_name, ug_percentage, admission_year
FROM   students
WHERE  ug_degree = 'BSc Mathematics';

CREATE OR REPLACE VIEW v_stats_background AS
SELECT student_id, reg_no, first_name, last_name, ug_percentage, admission_year
FROM   students
WHERE  ug_degree = 'BSc Statistics';

CREATE OR REPLACE VIEW v_datascience_background AS
SELECT student_id, reg_no, first_name, last_name, ug_percentage, admission_year
FROM   students
WHERE  ug_degree = 'BSc Data Science';

SELECT * FROM v_cs_background WHERE admission_year = 2026;

/* ---------------------------------------------------------------
   PART 2 - View over a JOIN (uses the ug_programs lookup table)
---------------------------------------------------------------- */
CREATE OR REPLACE VIEW v_students_by_stream AS
SELECT s.student_id, s.reg_no,
       CONCAT(s.first_name, ' ', s.last_name) AS full_name,
       s.ug_degree, p.stream_group, s.admission_year, s.status
FROM   students s
JOIN   ug_programs p ON p.ug_degree = s.ug_degree;

SELECT stream_group, COUNT(*) AS students
FROM   v_students_by_stream
GROUP  BY stream_group;

/* ---------------------------------------------------------------
   PART 3 - Reporting view (aggregation): batch summary
   One row per batch, one column per background
---------------------------------------------------------------- */
CREATE OR REPLACE VIEW v_batch_summary AS
SELECT admission_year                                        AS batch,
       COUNT(*)                                              AS total,
       SUM(ug_degree = 'BSc Mathematics')                    AS maths,
       SUM(ug_degree = 'BSc Statistics')                     AS stats,
       SUM(ug_degree IN ('BCA','BSc Computer Science'))      AS cs,
       SUM(ug_degree = 'BSc Data Science')                   AS data_science,
       ROUND(AVG(ug_percentage), 1)                          AS avg_ug_pct
FROM   students
GROUP  BY admission_year;

SELECT * FROM v_batch_summary ORDER BY batch;

/* ---------------------------------------------------------------
   PART 4 - Placement report (what a placement cell would ask for)
---------------------------------------------------------------- */
CREATE OR REPLACE VIEW v_placement_report AS
SELECT placed_company,
       COUNT(*)                    AS offers,
       ROUND(AVG(package_lpa), 1)  AS avg_lpa,
       MAX(package_lpa)            AS max_lpa
FROM   students
WHERE  placed_company IS NOT NULL
GROUP  BY placed_company;

SELECT * FROM v_placement_report ORDER BY avg_lpa DESC;

/* ---------------------------------------------------------------
   PART 5 - Window function inside a view: rank inside each batch
---------------------------------------------------------------- */
CREATE OR REPLACE VIEW v_batch_rank AS
SELECT admission_year, reg_no, first_name, last_name, ug_degree, cgpa,
       RANK() OVER (PARTITION BY admission_year ORDER BY cgpa DESC) AS batch_rank
FROM   students
WHERE  cgpa IS NOT NULL;

-- top 3 of every batch, in one line:
SELECT * FROM v_batch_rank WHERE batch_rank <= 3 ORDER BY admission_year, batch_rank;

/* ---------------------------------------------------------------
   PART 6 - SECURITY (the #1 real-world reason for views)
   Faculty/interns see masked data, never the raw table.
---------------------------------------------------------------- */
CREATE OR REPLACE VIEW v_students_public AS
SELECT reg_no,
       CONCAT(first_name, ' ', last_name)                                  AS full_name,
       CONCAT(LEFT(email, 2), '*****@', SUBSTRING_INDEX(email, '@', -1))   AS email_masked,
       ug_degree, admission_year, status
       -- dob, cgpa, package_lpa deliberately NOT exposed
FROM   students;

CREATE USER IF NOT EXISTS 'faculty'@'localhost' IDENTIFIED BY 'Faculty@123';
GRANT SELECT ON ds_dept.v_students_public TO 'faculty'@'localhost';

-- Now log in as faculty (mysql -u faculty -p) and try:
--   SELECT * FROM ds_dept.v_students_public LIMIT 3;   -- works, emails masked
--   SELECT * FROM ds_dept.students;                    -- ERROR 1142: SELECT command denied

/* ---------------------------------------------------------------
   PART 7 - WITH CHECK OPTION: a view that refuses bad writes
---------------------------------------------------------------- */
CREATE OR REPLACE VIEW v_batch_2026 AS
SELECT reg_no, first_name, last_name, gender, dob, email,
       ug_degree, ug_percentage, city, admission_year, status
FROM   students
WHERE  admission_year = 2026
WITH CHECK OPTION;

-- Works (row satisfies admission_year = 2026):
INSERT INTO v_batch_2026 (reg_no, first_name, last_name, gender, dob, email, ug_degree, ug_percentage, city, admission_year, status)
VALUES ('DS26999', 'Demo', 'Student', 'M', '2004-05-05', 'demo.student@example.edu', 'BCA', 80.00, 'Chennai', 2026, 'Active');

-- Fails with ERROR 1369 (CHECK OPTION failed) because the row would leave the view:
INSERT INTO v_batch_2026 (reg_no, first_name, last_name, gender, dob, email, ug_degree, ug_percentage, city, admission_year, status)
VALUES ('DS25999', 'Wrong', 'Batch', 'F', '2003-05-05', 'wrong.batch@example.edu', 'BCA', 80.00, 'Chennai', 2025, 'Active');

-- Clean up the demo row (deleting through the view works too):
DELETE FROM v_batch_2026 WHERE reg_no = 'DS26999';

/* ---------------------------------------------------------------
   PART 8 - "A view is live, not a copy" (great live demo)
---------------------------------------------------------------- */
SELECT COUNT(*) AS before_insert FROM v_cs_background;
INSERT INTO students (reg_no, first_name, last_name, gender, dob, email, ug_degree, ug_percentage, city, admission_year, graduation_year, status)
VALUES ('DS26998', 'Live', 'Demo', 'F', '2004-01-01', 'live.demo@example.edu', 'BSc Computer Science', 88.00, 'Chennai', 2026, 2028, 'Active');
SELECT COUNT(*) AS after_insert  FROM v_cs_background;   -- +1 without touching the view
DELETE FROM students WHERE reg_no = 'DS26998';

/* ---------------------------------------------------------------
   PART 9 - Look inside: metadata & which views are updatable
---------------------------------------------------------------- */
SHOW FULL TABLES WHERE Table_type = 'VIEW';
SHOW CREATE VIEW v_batch_summary\G
SELECT table_name, is_updatable, security_type, check_option
FROM   information_schema.views
WHERE  table_schema = 'ds_dept';

/* ---------------------------------------------------------------
   PART 10 - Things most people don't know
---------------------------------------------------------------- */
-- (a) A view is NOT faster by itself. MySQL merges it into your query:
EXPLAIN SELECT * FROM v_cs_background WHERE admission_year = 2026;   -- uses idx_year on the base table

-- (b) ORDER BY is allowed in a MySQL view, but is ignored if the outer query has its own ORDER BY.

-- (c) MySQL has NO materialized views. Poor-man's version = summary table + scheduled EVENT:
CREATE TABLE IF NOT EXISTS mv_batch_summary AS SELECT * FROM v_batch_summary;

SET GLOBAL event_scheduler = ON;   -- needs privilege

DROP EVENT IF EXISTS ev_refresh_mv_batch_summary;
DELIMITER $$
CREATE EVENT ev_refresh_mv_batch_summary
ON SCHEDULE EVERY 1 DAY
DO
BEGIN
    DELETE FROM mv_batch_summary;
    INSERT INTO mv_batch_summary SELECT * FROM v_batch_summary;
END$$
DELIMITER ;

-- (d) Zero-downtime schema change trick used in migrations:
--     RENAME TABLE students TO students_v2;
--     CREATE VIEW students AS SELECT * FROM students_v2;   -- old apps keep working