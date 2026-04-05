--
-- ALTER_TABLE
--

-- Clean up in case a prior regression run failed
SET client_min_messages TO 'warning';
DROP ROLE IF EXISTS regress_alter_table_user1;
RESET client_min_messages;

CREATE USER regress_alter_table_user1;

--
-- add attribute
--

CREATE TABLE attmp (initial int4);

COMMENT ON TABLE attmp_wrong IS 'table comment';
COMMENT ON TABLE attmp IS 'table comment';
COMMENT ON TABLE attmp IS NULL;

ALTER TABLE attmp ADD COLUMN xmin integer; -- fails

ALTER TABLE attmp ADD COLUMN a int4 default 3;

ALTER TABLE attmp ADD COLUMN b name;

ALTER TABLE attmp ADD COLUMN c text;

ALTER TABLE attmp ADD COLUMN d float8;

ALTER TABLE attmp ADD COLUMN e float4;

ALTER TABLE attmp ADD COLUMN f int2;

ALTER TABLE attmp ADD COLUMN g polygon;

ALTER TABLE attmp ADD COLUMN i char;

ALTER TABLE attmp ADD COLUMN k int4;

ALTER TABLE attmp ADD COLUMN l tid;

ALTER TABLE attmp ADD COLUMN m xid;

ALTER TABLE attmp ADD COLUMN n oidvector;

--ALTER TABLE attmp ADD COLUMN o lock;
ALTER TABLE attmp ADD 
