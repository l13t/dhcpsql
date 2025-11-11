-- Sample data for DHCP server
-- This file contains example static leases and options

USE dhcp;

-- Insert some sample static leases
-- Format: MAC address as bigint, IP address as bigint, class
INSERT INTO staticleases (mac, ip, class) VALUES
  (0x001122334455, INET_ATON('192.168.1.100'), 1),
  (0x001122334456, INET_ATON('192.168.1.101'), 1),
  (0x001122334457, INET_ATON('192.168.1.102'), 2);

-- Insert human-readable static leases for easier management
INSERT INTO staticleases_readable (mac, ip, class) VALUES
  ('001122334455', '192.168.1.100', 1),
  ('001122334456', '192.168.1.101', 1),
  ('001122334457', '192.168.1.102', 2);

-- Insert some sample DHCP options
-- Class 0 = default/global options
-- Class 1 = workstation class
-- Class 2 = server class

-- Global DNS servers
INSERT INTO options (class, code, data) VALUES
  (0, 6, INET_ATON('8.8.8.8')),
  (0, 6, INET_ATON('8.8.4.4'));

-- Global subnet mask
INSERT INTO options (class, code, data) VALUES
  (0, 1, INET_ATON('255.255.255.0'));

-- Global router/gateway
INSERT INTO options (class, code, data) VALUES
  (0, 3, INET_ATON('192.168.1.1'));

-- Global domain name
INSERT INTO options (class, code, data) VALUES
  (0, 15, 'local.domain');

-- Lease time (in seconds) - 24 hours
INSERT INTO options (class, code, data) VALUES
  (0, 51, '86400');

-- Class-specific options for workstations (class 1)
INSERT INTO options (class, code, data) VALUES
  (1, 42, INET_ATON('192.168.1.1'));  -- NTP server

-- Class-specific options for servers (class 2)  
INSERT INTO options (class, code, data) VALUES
  (2, 42, INET_ATON('192.168.1.1')),  -- NTP server
  (2, 51, '604800');                   -- 7 day lease for servers

-- NetBIOS name server (WINS) for Windows clients
INSERT INTO options (class, code, data) VALUES
  (0, 44, INET_ATON('192.168.1.1'));

-- Sample vendor-specific options
-- INSERT INTO options (class, code, data) VALUES
--   (0, 43, 'vendor-specific-data-here');

-- Display inserted data
SELECT 'Static Leases (readable format):' as Info;
SELECT mac, ip, class FROM staticleases_readable;

SELECT 'DHCP Options by class:' as Info;
SELECT 
  o.class,
  m.name as option_name,
  o.code,
  o.data
FROM options o
LEFT JOIN metaoptions m ON o.code = m.id
ORDER BY o.class, o.code;
