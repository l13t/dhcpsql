/*
 * static_leases.c -- Couple of functions to assist with storing and
 * retrieving data for static leases
 *
 * Wade Berrier <wberrier@myrealbox.com> September 2004
 *
 * Updated for DHCPsql Stefan de Konink <stefan@konink.de> August 2006
 *
 */


#include <stdlib.h>
#include <stdio.h>
#include <string.h>
#include <mysql.h>
#include <arpa/inet.h>

#include "udhcp/static_leases.h"
#include "udhcp/dhcpd.h"

/* Connections are short-lived; bound waits so database outages do not hang DHCP. */
static MYSQL *connect_database(void)
{
	MYSQL *conn = mysql_init(NULL);
	unsigned int timeout = 2;
	if (!conn) return NULL;
	mysql_options(conn, MYSQL_OPT_CONNECT_TIMEOUT, &timeout);
	mysql_options(conn, MYSQL_OPT_READ_TIMEOUT, &timeout);
	mysql_options(conn, MYSQL_OPT_WRITE_TIMEOUT, &timeout);
	if (!mysql_real_connect(conn, server_config.dbserver, server_config.user,
		server_config.password, server_config.database, 0, NULL, 0)) {
		fprintf(stderr, "%s\n", mysql_error(conn));
		mysql_close(conn);
		return NULL;
	}
	return conn;
}

int addStaticLease(struct static_lease **lease_struct, uint8_t *mac, uint32_t *ip)
{
	char query[512];
	MYSQL *conn = connect_database();
	int result, len;
	(void)lease_struct;
	if (!conn) return 0;
	if (server_config.table_efficient)
		len = snprintf(query, sizeof(query), "INSERT INTO %s (mac, ip) VALUES (0x%02x%02x%02x%02x%02x%02x, %u)", server_config.table_staticleases, mac[0], mac[1], mac[2], mac[3], mac[4], mac[5], ntohl(*ip));
	else
		len = snprintf(query, sizeof(query), "INSERT INTO %s (mac, ip) VALUES ('%02x%02x%02x%02x%02x%02x', INET_NTOA(%u))", server_config.table_staticleases, mac[0], mac[1], mac[2], mac[3], mac[4], mac[5], ntohl(*ip));
	result = len >= 0 && (size_t)len < sizeof(query) && mysql_query(conn, query) == 0;
	if (!result) fprintf(stderr, "Static lease insert failed: %s\n", mysql_error(conn));
	mysql_close(conn);
	return result;
}

uint32_t getIpByMac(struct static_lease *lease_struct, void *arg)
{
	uint8_t *mac = arg;
	uint32_t ip = STATIC_LEASE_ERROR;
	char query[512];
	int len;
	MYSQL *conn = connect_database();
	MYSQL_RES *res;
	MYSQL_ROW row;
	(void)lease_struct;
	if (!conn) return STATIC_LEASE_ERROR;
	if (server_config.table_efficient)
		len = snprintf(query, sizeof(query), "SELECT INET_NTOA(ip) FROM %s WHERE mac = 0x%02x%02x%02x%02x%02x%02x", server_config.table_staticleases, mac[0], mac[1], mac[2], mac[3], mac[4], mac[5]);
	else
		len = snprintf(query, sizeof(query), "SELECT ip FROM %s WHERE LOWER(mac) = '%02x%02x%02x%02x%02x%02x'", server_config.table_staticleases, mac[0], mac[1], mac[2], mac[3], mac[4], mac[5]);
	if (len < 0 || (size_t)len >= sizeof(query) || mysql_query(conn, query)) goto out;
	res = mysql_store_result(conn);
	if (!res) goto out;
	row = mysql_fetch_row(res);
	if (!row) {
		if (!mysql_errno(conn)) ip = 0;
	} else {
		struct in_addr addr;
		if (row[0] && inet_pton(AF_INET, row[0], &addr) == 1 &&
		    addr.s_addr != 0 && addr.s_addr != STATIC_LEASE_ERROR)
			ip = addr.s_addr;
	}
	mysql_free_result(res);
out:
	if (ip == STATIC_LEASE_ERROR) fprintf(stderr, "Static lease lookup failed: %s\n", mysql_error(conn));
	mysql_close(conn);
	return ip;
}

/* A failed reservation check must never make an address available. */
uint32_t reservedIp(struct static_lease *lease_struct, uint32_t ip)
{
	char query[512];
	int len;
	uint32_t reserved = STATIC_LEASE_ERROR;
	MYSQL *conn = connect_database();
	MYSQL_RES *res;
	(void)lease_struct;
	if (!conn) return reserved;
	if (server_config.table_efficient)
		len = snprintf(query, sizeof(query), "SELECT 1 FROM %s WHERE ip = %u LIMIT 1", server_config.table_staticleases, ntohl(ip));
	else
		len = snprintf(query, sizeof(query), "SELECT 1 FROM %s WHERE ip = INET_NTOA(%u) LIMIT 1", server_config.table_staticleases, ntohl(ip));
	if (len < 0 || (size_t)len >= sizeof(query) || mysql_query(conn, query)) goto out;
	res = mysql_store_result(conn);
	if (!res) goto out;
	reserved = mysql_num_rows(res) != 0;
	mysql_free_result(res);
out:
	mysql_close(conn);
	return reserved;
}

#ifdef UDHCP_DEBUG
void printStaticLeases(struct static_lease **arg)
{
	char query[512];
	MYSQL *conn = connect_database();
	MYSQL_RES *res;
	MYSQL_ROW row;
	int len;
	(void)arg;
	if (!conn) return;
	len = snprintf(query, sizeof(query), "SELECT mac, %s FROM %s",
		server_config.table_efficient ? "INET_NTOA(ip)" : "ip", server_config.table_staticleases);
	if (len >= 0 && (size_t)len < sizeof(query) && !mysql_query(conn, query)) {
		res = mysql_store_result(conn);
		if (res) {
			while ((row = mysql_fetch_row(res)))
				printf("Static lease: %s %s\n", row[0] ? row[0] : "NULL", row[1] ? row[1] : "NULL");
			mysql_free_result(res);
		}
	}
	mysql_close(conn);
}
#endif
