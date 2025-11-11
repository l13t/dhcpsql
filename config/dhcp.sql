CREATE DATABASE dhcp;
GRANT ALL ON dhcp.* TO dhcp@localhost IDENTIFIED BY "dhcp";

USE dhcp;

CREATE TABLE `options` (
`id` int(11) NOT NULL auto_increment,
`class` int(11) NOT NULL,
`code` tinyint(5) NOT NULL,
`data` varchar(255) NOT NULL,
PRIMARY KEY (`id`)
) ENGINE=MyISAM DEFAULT CHARSET=utf8;

CREATE TABLE `staticleases` (
`mac` bigint(11) NOT NULL,
`ip` bigint(11) NOT NULL,
`class` int(11) default NULL,
PRIMARY KEY (`mac`),
UNIQUE KEY `ip` (`ip`)
) ENGINE=MyISAM DEFAULT CHARSET=utf8;

CREATE TABLE `staticleases_readable` (
`mac` char(12) NOT NULL,
`ip` varchar(15) NOT NULL,
`class` int(11) default NULL,
PRIMARY KEY (`mac`),
UNIQUE KEY `ip` (`ip`)
) ENGINE=MyISAM DEFAULT CHARSET=utf8;


SET @OPTION_IP=1;
SET @OPTION_IP_PAIR=2;
SET @OPTION_STRING=3;
SET @OPTION_BOOLEAN=4;
SET @OPTION_U8=5;
SET @OPTION_U16=6;
SET @OPTION_S16=7;
SET @OPTION_U32=8;
SET @OPTION_S32=9;
SET @OPTION_REQ=16;
SET @OPTION_LIST=32;

create table metaoptions(id  TINYINT unsigned not null, name varchar(64) not null, mask TINYINT unsigned not null, primary key(id));

insert into metaoptions(id, name, mask) values (1, "Subnet Mask", @OPTION_IP | @OPTION_REQ);
insert into metaoptions(id, name, mask) values (2, "Time Offset", @OPTION_S32);
insert into metaoptions(id, name, mask) values (3, "Router", @OPTION_IP | @OPTION_LIST | @OPTION_REQ);
insert into metaoptions(id, name, mask) values (4, "Time Server", @OPTION_IP | @OPTION_LIST);
insert into metaoptions(id, name, mask) values (5, "Name Server", @OPTION_IP | @OPTION_LIST);
insert into metaoptions(id, name, mask) values (6, "Domain Name Server", @OPTION_IP | @OPTION_LIST | @OPTION_REQ);
insert into metaoptions(id, name, mask) values (7, "Log Server", @OPTION_IP | @OPTION_LIST);
insert into metaoptions(id, name, mask) values (8, "Cookie Server", @OPTION_IP | @OPTION_LIST);
insert into metaoptions(id, name, mask) values (9, "LPR Server", @OPTION_IP | @OPTION_LIST);
insert into metaoptions(id, name, mask) values (10, "Impress Server", @OPTION_IP | @OPTION_LIST);
insert into metaoptions(id, name, mask) values (11, "Resource Location Server", @OPTION_IP | @OPTION_LIST);
insert into metaoptions(id, name, mask) values (12, "Host Name", @OPTION_STRING | @OPTION_REQ);
insert into metaoptions(id, name, mask) values (13, "Boot File Size", @OPTION_U16);
insert into metaoptions(id, name, mask) values (14, "Merit Dump File", @OPTION_STRING);
insert into metaoptions(id, name, mask) values (15, "Domain Name", @OPTION_STRING | @OPTION_REQ);
insert into metaoptions(id, name, mask) values (16, "Swap Server", @OPTION_IP);
insert into metaoptions(id, name, mask) values (17, "Root Path", @OPTION_STRING);
insert into metaoptions(id, name, mask) values (18, "Extensions Path", @OPTION_STRING);
insert into metaoptions(id, name, mask) values (19, "IP Forwarding", @OPTION_BOOLEAN);
insert into metaoptions(id, name, mask) values (20, "Non-Local Source Routing", @OPTION_BOOLEAN);
insert into metaoptions(id, name, mask) values (21, "Policy Filter", @OPTION_IP_PAIR | @OPTION_LIST);
insert into metaoptions(id, name, mask) values (22, "Maximum Datagram Reassembly Size", @OPTION_U16);
insert into metaoptions(id, name, mask) values (23, "Default IP Time-to-live", @OPTION_U8);
insert into metaoptions(id, name, mask) values (24, "Path MTU Aging Timeout", @OPTION_U32);
insert into metaoptions(id, name, mask) values (25, "Path MTU Plateau Table", @OPTION_U16 | @OPTION_LIST);
insert into metaoptions(id, name, mask) values (26, "Interface MTU", @OPTION_U16);
insert into metaoptions(id, name, mask) values (27, "All Subnets are Local", @OPTION_BOOLEAN);
insert into metaoptions(id, name, mask) values (28, "Broadcast Address", @OPTION_IP | @OPTION_REQ);
insert into metaoptions(id, name, mask) values (29, "Perform Mask Discovery", @OPTION_BOOLEAN);
insert into metaoptions(id, name, mask) values (30, "Mask Supplier", @OPTION_BOOLEAN);
insert into metaoptions(id, name, mask) values (31, "Perform Router Discovery", @OPTION_BOOLEAN);
insert into metaoptions(id, name, mask) values (32, "Router Solicitation Address", @OPTION_IP);
insert into metaoptions(id, name, mask) values (33, "Static Route", @OPTION_IP_PAIR | @OPTION_LIST);
insert into metaoptions(id, name, mask) values (34, "Trailer Encapsulation", @OPTION_BOOLEAN);
insert into metaoptions(id, name, mask) values (35, "ARP Cache Timeout", @OPTION_U32);
insert into metaoptions(id, name, mask) values (36, "Ethernet Encapsulation", @OPTION_BOOLEAN);
insert into metaoptions(id, name, mask) values (37, "TCP Default TTL", @OPTION_U8);
insert into metaoptions(id, name, mask) values (38, "TCP Keepalive Interval", @OPTION_U32);
insert into metaoptions(id, name, mask) values (39, "TCP Keepalive Garbage", @OPTION_BOOLEAN);
insert into metaoptions(id, name, mask) values (40, "Network Information Service Domain", @OPTION_STRING | @OPTION_REQ);
insert into metaoptions(id, name, mask) values (41, "Network Information Servers", @OPTION_IP | @OPTION_LIST | @OPTION_REQ);
insert into metaoptions(id, name, mask) values (42, "Network Time Protocol Servers", @OPTION_IP | @OPTION_LIST | @OPTION_REQ);
insert into metaoptions(id, name, mask) values (43, "Vendor Specific Information", @OPTION_STRING);
insert into metaoptions(id, name, mask) values (44, "NetBIOS over TCP/IP Name Server", @OPTION_IP | @OPTION_LIST);
insert into metaoptions(id, name, mask) values (45, "NetBIOS over TCP/IP Datagram Distribution Server", @OPTION_IP | @OPTION_LIST);
insert into metaoptions(id, name, mask) values (46, "NetBIOS over TCP/IP Node Type", @OPTION_U8);
insert into metaoptions(id, name, mask) values (47, "NetBIOS over TCP/IP Scope ??", @OPTION_S16 | @OPTION_LIST);
insert into metaoptions(id, name, mask) values (48, "X Window System Font Server", @OPTION_IP | @OPTION_LIST);
insert into metaoptions(id, name, mask) values (49, "X Window System Display Manager", @OPTION_IP | @OPTION_LIST);
insert into metaoptions(id, name, mask) values (64, "Network Information Service+ Domain", @OPTION_STRING);
insert into metaoptions(id, name, mask) values (65, "Network Information Service+ Servers", @OPTION_IP | @OPTION_LIST);
insert into metaoptions(id, name, mask) values (68, "Mobile IP Home Agent", @OPTION_IP | @OPTION_LIST);
insert into metaoptions(id, name, mask) values (69, "Simple Mail Transport Protocol (SMTP) Server", @OPTION_IP |@OPTION_LIST);
insert into metaoptions(id, name, mask) values (70, "Post Office Protocol (POP3) Server", @OPTION_IP |@OPTION_LIST);
insert into metaoptions(id, name, mask) values (71, "Network News Transport Protocol (NNTP) Server", @OPTION_IP |@OPTION_LIST);
insert into metaoptions(id, name, mask) values (72, "Default World Wide Web (WWW) Server", @OPTION_IP |@OPTION_LIST);
insert into metaoptions(id, name, mask) values (73, "Default Finger Server", @OPTION_IP |@OPTION_LIST);
insert into metaoptions(id, name, mask) values (74, "Default Internet Relay Chat (IRC) Server", @OPTION_IP | @OPTION_LIST);
insert into metaoptions(id, name, mask) values (75, "StreetTalk Server", @OPTION_IP | @OPTION_LIST);
insert into metaoptions(id, name, mask) values (76, "StreetTalk Directory Assistance (STDA) Server", @OPTION_IP | @OPTION_LIST);
insert into metaoptions(id, name, mask) values (50, "Requested IP Address", @OPTION_IP);
insert into metaoptions(id, name, mask) values (51, "IP Address Lease Time", @OPTION_U32);
insert into metaoptions(id, name, mask) values (52, "Option Overload", @OPTION_U8);
insert into metaoptions(id, name, mask) values (66, "TFTP server name", @OPTION_STRING);
insert into metaoptions(id, name, mask) values (67, "Bootfile name", @OPTION_STRING);
insert into metaoptions(id, name, mask) values (53, "DHCP Message Type", @OPTION_U8);
insert into metaoptions(id, name, mask) values (54, "Server Identifier", @OPTION_IP);
insert into metaoptions(id, name, mask) values (55, "Parameter Request List ??", @OPTION_U8 | @OPTION_LIST | @OPTION_REQ);
insert into metaoptions(id, name, mask) values (56, "Message", @OPTION_STRING);
insert into metaoptions(id, name, mask) values (57, "Maximum DHCP Message Size", @OPTION_U16);
insert into metaoptions(id, name, mask) values (58, "Renewal (T1) Time Value", @OPTION_U32);
insert into metaoptions(id, name, mask) values (59, "Rebinding (T2) Time Value", @OPTION_U32);
insert into metaoptions(id, name, mask) values (60, "Vendor class identifier", @OPTION_STRING);
insert into metaoptions(id, name, mask) values (61, "Client-identifier", @OPTION_STRING);

