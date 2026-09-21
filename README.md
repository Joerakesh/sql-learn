## Method to insert data via csv

```sql
USE ds_dept;
LOAD DATA LOCAL INFILE '/home/joerakesh/sql-learn/students.csv'
INTO TABLE students
FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '"'
LINES TERMINATED BY '\r\n'
IGNORE 1 LINES
(student_id, reg_no, first_name, last_name, gender, dob, email, ug_degree, ug_percentage, city,
 admission_year, @grad, status, @cgpa, @company, @pkg)
SET graduation_year = NULLIF(@grad,''), cgpa = NULLIF(@cgpa,''),
    placed_company = NULLIF(@company,''), package_lpa = NULLIF(@pkg,'');
```
