-- ==========================================================
--  SQL INDEXES DEMO  (10 million students, MySQL Workbench)
-- ==========================================================
--  Idea: an index is like the index at the back of a book.
--  Without it MySQL reads every row (full table scan).
--  With it MySQL jumps straight to the matching row.
--  With 10 rows you can't feel the difference. With 10 million you can.
-- ==========================================================


-- ----------------------------------------------------------
-- PART 0: SETUP  (do this BEFORE the seminar, not live)
-- ----------------------------------------------------------

CREATE DATABASE IF NOT EXISTS sql_index_lab;
USE sql_index_lab;

DROP TABLE IF EXISTS students_million;
CREATE TABLE students_million (
    student_id   INT PRIMARY KEY,          -- PRIMARY KEY = automatic index
    student_name VARCHAR(100) NOT NULL,
    department   VARCHAR(50)  NOT NULL,
    city         VARCHAR(50)  NOT NULL,
    email        VARCHAR(150) NOT NULL,    -- NO index yet (on purpose)
    cgpa         DECIMAL(4,2) NOT NULL
);

-- Helper table: digits 0-9. Cross-joining it 6 times gives 1,000,000
-- numbers (10^6). We repeat that 10 times (10 batches) = 10,000,000 rows.
DROP TABLE IF EXISTS digits;
CREATE TABLE digits (n INT PRIMARY KEY);
INSERT INTO digits (n) VALUES (0),(1),(2),(3),(4),(5),(6),(7),(8),(9);


-- Insert in batches of 1 million. One giant insert can time out
-- ("Error 2013: Lost connection to MySQL server during query").
DROP PROCEDURE IF EXISTS load_students;
DELIMITER $$
CREATE PROCEDURE load_students(IN total_batches INT)
BEGIN
    DECLARE b INT DEFAULT 0;
    WHILE b < total_batches DO
        INSERT INTO students_million
        SELECT
            g.num + 1,
            CONCAT('Student_', g.num + 1),
            CASE MOD(g.num, 4)
                WHEN 0 THEN 'Data Science'
                WHEN 1 THEN 'Computer Science'
                WHEN 2 THEN 'Information Technology'
                ELSE 'Statistics'
            END,
            CASE MOD(g.num, 5)
                WHEN 0 THEN 'Chennai'
                WHEN 1 THEN 'Bangalore'
                WHEN 2 THEN 'Mumbai'
                WHEN 3 THEN 'Delhi'
                ELSE 'Hyderabad'
            END,
            CONCAT('student_', g.num + 1, '@example.com'),
            CAST(6.00 + MOD(g.num, 401) / 100 AS DECIMAL(4,2))
        FROM (
            SELECT d1.n + d2.n*10 + d3.n*100 + d4.n*1000
                 + d5.n*10000 + d6.n*100000 + b*1000000 AS num
            FROM digits d1 CROSS JOIN digits d2 CROSS JOIN digits d3
                 CROSS JOIN digits d4 CROSS JOIN digits d5 CROSS JOIN digits d6
        ) AS g;
        SET b = b + 1;
    END WHILE;
END$$
DELIMITER ;

-- Takes a few minutes. If Workbench disconnects, raise
-- Edit > Preferences > SQL Editor > "DBMS connection read timeout" to 600,
-- or run with 1 batch at a time and repeat (change the start batch).
CALL load_students(10);

-- Sanity check
SELECT COUNT(*) AS total_students FROM students_million;      -- 10,000,000
SELECT * FROM students_million LIMIT 10;


-- ----------------------------------------------------------
-- PART 1: WHY DO WE NEED AN INDEX?  (live demo)
-- ----------------------------------------------------------

-- 1A. Search by PRIMARY KEY: fast, because it is already indexed
EXPLAIN SELECT * FROM students_million WHERE student_id = 9999999;
--   type = const, key = PRIMARY, rows = 1
SELECT * FROM students_million WHERE student_id = 9999999;

-- 1B. Search by EMAIL: NO index yet -> full table scan
EXPLAIN SELECT * FROM students_million WHERE email = 'student_9999999@example.com';
--   type = ALL, key = NULL, rows ~ 10,000,000   (MySQL reads every row)
SELECT * FROM students_million WHERE email = 'student_9999999@example.com';
--   NOTE THE TIME: this is the "slow" number (seconds)


-- ----------------------------------------------------------
-- PART 2: CREATE THE INDEX
-- ----------------------------------------------------------

-- UNIQUE index: fast lookup AND blocks duplicate emails
CREATE UNIQUE INDEX idx_email ON students_million (email);
--   NOTE THE TIME: building an index costs time and disk space

SHOW INDEX FROM students_million;   -- PRIMARY + idx_email


-- ----------------------------------------------------------
-- PART 3: SAME QUERY, AFTER THE INDEX
-- ----------------------------------------------------------

EXPLAIN SELECT * FROM students_million WHERE email = 'student_9999999@example.com';
--   type = const, key = idx_email, rows = 1
SELECT * FROM students_million WHERE email = 'student_9999999@example.com';
--   Same query, now ~0.00 sec instead of seconds

-- Optional: real measured execution (MySQL 8.0.18+)
EXPLAIN ANALYZE SELECT * FROM students_million WHERE email = 'student_9999999@example.com';


-- ----------------------------------------------------------
-- PART 4: WHEN AN INDEX DOES NOT HELP MUCH  (low selectivity)
-- ----------------------------------------------------------
-- department has only 4 distinct values, so each one matches
-- ~2.5 million rows. An index on it helps far less than on email.

EXPLAIN SELECT * FROM students_million WHERE department = 'Data Science';
--   type = ALL (full scan) - no index yet

CREATE INDEX idx_department ON students_million (department);

EXPLAIN SELECT * FROM students_million WHERE department = 'Data Science';
--   MySQL may still choose a full scan, because reading 25% of the
--   table through the index is not cheaper. Good discussion point.

-- Index shines when the result is SMALL:
EXPLAIN SELECT * FROM students_million
WHERE department = 'Data Science' AND student_id BETWEEN 1 AND 100;


-- ----------------------------------------------------------
-- PART 5: COST OF INDEXES + CLEANUP
-- ----------------------------------------------------------
-- Every index: uses extra disk, slows INSERT/UPDATE/DELETE.
-- Index columns you often search, join, or sort by. Not everything.

DROP INDEX idx_department ON students_million;
DROP INDEX idx_email ON students_million;
-- (drop and recreate idx_email to repeat the demo)
