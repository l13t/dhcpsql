-- Test data for DHCP server integration tests
-- This file contains comprehensive test data for validating DHCP functionality

USE dhcp_test;

-- Clear existing data
DELETE FROM options;
DELETE FROM staticleases;
DELETE FROM staticleases_readable;

-- Test static leases for integration testing
-- MAC addresses using test ranges to avoid conflicts
INSERT INTO staticleases (mac, ip, class) VALUES
  -- Test client 1: Standard workstation
  (0x001122aabbcc, INET_ATON('172.20.1.100'), 1),
  -- Test client 2: Server class
  (0x001122aabbdd, INET_ATON('172.20.1.101'), 2),
  -- Test client 3: Default class
  (0x001122aabbee, INET_ATON('172.20.1.102'), 0),
  -- Test client 4: Special class for testing
  (0x001122aabbff, INET_ATON('172.20.1.103'), 3),
  -- Test client 5: Load testing base
  (0x001122cccccc, INET_ATON('172.20.1.104'), 1);

-- Human-readable static leases for easier test management
INSERT INTO staticleases_readable (mac, ip, class) VALUES
  ('001122aabbcc', '172.20.1.100', 1),
  ('001122aabbdd', '172.20.1.101', 2),
  ('001122aabbee', '172.20.1.102', 0),
  ('001122aabbff', '172.20.1.103', 3),
  ('001122cccccc', '172.20.1.104', 1);

-- Global DHCP options for testing (class 0)
INSERT INTO options (class, code, data) VALUES
  -- Subnet mask for test network
  (0, 1, INET_ATON('255.255.0.0')),
  -- Router/Gateway
  (0, 3, INET_ATON('172.20.0.1')),
  -- DNS servers (primary and secondary)
  (0, 6, INET_ATON('8.8.8.8')),
  (0, 6, INET_ATON('8.8.4.4')),
  -- Domain name
  (0, 15, 'test.local'),
  -- Broadcast address
  (0, 28, INET_ATON('172.20.255.255')),
  -- Lease time (1 hour for fast testing)
  (0, 51, '3600'),
  -- DHCP server identifier
  (0, 54, INET_ATON('172.20.0.10')),
  -- Renewal time (30 minutes)
  (0, 58, '1800'),
  -- Rebinding time (45 minutes)
  (0, 59, '2700');

-- Class 1 options (Workstations)
INSERT INTO options (class, code, data) VALUES
  (1, 42, INET_ATON('172.20.0.1')),    -- NTP server
  (1, 44, INET_ATON('172.20.0.1')),    -- NetBIOS name server
  (1, 15, 'workstation.test.local'),   -- Domain name override
  (1, 51, '7200');                      -- 2 hour lease

-- Class 2 options (Servers)
INSERT INTO options (class, code, data) VALUES
  (2, 42, INET_ATON('172.20.0.1')),    -- NTP server
  (2, 15, 'server.test.local'),        -- Domain name override
  (2, 51, '86400'),                     -- 24 hour lease
  (2, 69, INET_ATON('172.20.0.1')),    -- SMTP server
  (2, 70, INET_ATON('172.20.0.1'));    -- POP3 server

-- Class 3 options (Special test class)
INSERT INTO options (class, code, data) VALUES
  (3, 15, 'special.test.local'),       -- Domain name override
  (3, 51, '300'),                       -- 5 minute lease for quick testing
  (3, 42, INET_ATON('172.20.0.2'));    -- Different NTP server

-- Additional test options for edge cases
INSERT INTO options (class, code, data) VALUES
  -- Vendor-specific information
  (0, 43, 'TEST-VENDOR-DATA'),
  -- NetBIOS node type
  (0, 46, '8'),
  -- Maximum DHCP message size
  (0, 57, '576'),
  -- Client identifier test
  (0, 61, 'test-client-id');

-- Test data for load testing - create multiple static leases
-- This will help test performance with many database records
INSERT INTO staticleases (mac, ip, class)
SELECT
  0x001122000000 + n as mac,
  INET_ATON('172.20.2.1') + n as ip,
  (n % 4) as class
FROM (
  SELECT a.N + b.N * 10 + c.N * 100 as n
  FROM
    (SELECT 0 as N UNION SELECT 1 UNION SELECT 2 UNION SELECT 3 UNION SELECT 4 UNION SELECT 5 UNION SELECT 6 UNION SELECT 7 UNION SELECT 8 UNION SELECT 9) a,
    (SELECT 0 as N UNION SELECT 1 UNION SELECT 2 UNION SELECT 3 UNION SELECT 4 UNION SELECT 5 UNION SELECT 6 UNION SELECT 7 UNION SELECT 8 UNION SELECT 9) b,
    (SELECT 0 as N UNION SELECT 1 UNION SELECT 2) c
) numbers
WHERE n BETWEEN 1 AND 200;

-- Create test views for easier test validation
CREATE VIEW test_lease_summary AS
SELECT
  class,
  COUNT(*) as lease_count,
  MIN(INET_NTOA(ip)) as min_ip,
  MAX(INET_NTOA(ip)) as max_ip
FROM staticleases
GROUP BY class
ORDER BY class;

CREATE VIEW test_options_summary AS
SELECT
  o.class,
  COUNT(*) as option_count,
  GROUP_CONCAT(CONCAT(m.name, '(', o.code, ')') SEPARATOR ', ') as options_list
FROM options o
LEFT JOIN metaoptions m ON o.code = m.id
GROUP BY o.class
ORDER BY o.class;

-- Create test procedures for validation
DELIMITER //

CREATE PROCEDURE validate_test_setup()
BEGIN
  DECLARE static_lease_count INT DEFAULT 0;
  DECLARE options_count INT DEFAULT 0;
  DECLARE result_status VARCHAR(20) DEFAULT 'PASS';

  SELECT COUNT(*) INTO static_lease_count FROM staticleases;
  SELECT COUNT(*) INTO options_count FROM options;

  IF static_lease_count < 205 THEN
    SET result_status = 'FAIL';
  END IF;

  IF options_count < 20 THEN
    SET result_status = 'FAIL';
  END IF;

  SELECT
    result_status as test_status,
    static_lease_count as leases,
    options_count as options,
    'Test data validation complete' as message;
END //

CREATE PROCEDURE cleanup_test_leases()
BEGIN
  -- Remove test leases but keep the core test data
  DELETE FROM staticleases WHERE mac >= 0x001122000000 AND mac <= 0x001122000200;
  SELECT 'Test lease cleanup complete' as message, ROW_COUNT() as deleted_records;
END //

DELIMITER ;

-- Insert validation data
INSERT INTO staticleases_readable (mac, ip, class) VALUES
  ('TEST001', '172.20.99.1', 99),
  ('TEST002', '172.20.99.2', 99);

-- Test edge cases
INSERT INTO options (class, code, data) VALUES
  -- Test maximum values
  (99, 51, '4294967295'),  -- Maximum lease time
  (99, 57, '65535'),       -- Maximum message size
  -- Test minimum values
  (99, 51, '60'),          -- Minimum reasonable lease time
  -- Test string edge cases
  (99, 15, 'a'),           -- Single character domain
  (99, 15, 'very-long-domain-name-for-testing-maximum-length-handling.example.com'); -- Long domain

-- Display test data summary
SELECT 'TEST DATA LOADED SUCCESSFULLY' as status;
SELECT '=========================' as separator;

SELECT 'Static Leases by Class:' as info;
SELECT * FROM test_lease_summary;

SELECT 'Options by Class:' as info;
SELECT * FROM test_options_summary;

SELECT 'Validation Result:' as info;
CALL validate_test_setup();

SELECT 'Test data setup complete. Ready for integration testing.' as final_message;
