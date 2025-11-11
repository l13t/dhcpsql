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

/* Takes the address of the pointer to the static_leases table,
 *   Address to a 6 byte mac address
 *   Address to a 4 byte ip address */
int addStaticLease(struct static_lease **lease_struct, uint8_t *mac, uint32_t *ip)
{

	char query[256];
	MYSQL *conn;

	(void) lease_struct;

	conn = mysql_init(NULL);

	/* Connect to database */
	if (!mysql_real_connect(conn, server_config.dbserver, server_config.user, server_config.password, server_config.database, 0, NULL, 0)) {
		fprintf(stderr, "%s\n", mysql_error(conn));
		exit(0);
	}

	if (server_config.table_efficient)
		snprintf(query, 256, "INSERT INTO %s (mac, ip) VALUES (0x%02x%02x%02x%02x%02x%02x, %u)", server_config.table_staticleases, mac[0],mac[1],mac[2],mac[3],mac[4],mac[5], *ip);
	else
		snprintf(query, 256, "INSERT INTO %s (mac, ip) VALUES (\"%02x%02x%02x%02x%02x%02x\", INET_NTOA(%u))", server_config.table_staticleases, mac[0],mac[1],mac[2],mac[3],mac[4],mac[5], *ip);
#ifdef UDHCP_DEBUG
	printf("%s\n", query);
#endif
	/* send SQL quer */
	if (mysql_query(conn, query)) {
		fprintf(stderr, "%s\n", mysql_error(conn));
		return 0;
	}
	
	mysql_close(conn);
	
	return 1;

}

/* Check to see if a mac has an associated static lease */
uint32_t getIpByMac(struct static_lease *lease_struct, void *arg)
{
	uint32_t return_ip;
	uint8_t *mac = arg;

	(void) lease_struct;

	return_ip = 0;

	char query[256];
	
	MYSQL *conn;
	MYSQL_RES *res;
	MYSQL_ROW row;

	conn = mysql_init(NULL);

	/* Connect to database */
	if (!mysql_real_connect(conn, server_config.dbserver, server_config.user, server_config.password, server_config.database, 0, NULL, 0)) {
		fprintf(stderr, "%s\n", mysql_error(conn));
		exit(0);
	}

	if (server_config.table_efficient)
		snprintf(query, 256, "SELECT ip FROM %s WHERE mac = 0x%02x%02x%02x%02x%02x%02x", server_config.table_staticleases, mac[0],mac[1],mac[2],mac[3],mac[4],mac[5]);
	else
		snprintf(query, 256, "SELECT INET_ATON(ip) FROM %s WHERE LOWER(mac) = \"%02x%02x%02x%02x%02x%02x\"", server_config.table_staticleases, mac[0],mac[1],mac[2],mac[3],mac[4],mac[5]);
#ifdef UDHCP_DEBUG
	printf("%s\n", query);
#endif

	/* send SQL query */
	if (mysql_query(conn, query)) {
		fprintf(stderr, "%s\n", mysql_error(conn));
		return_ip = 0;
	} else {
		struct in_addr addr;
		res = mysql_use_result(conn);
		
		/* Should be only one row, otherwise take the last I guess ;) */
		while ((row = mysql_fetch_row(res)) != NULL) {
			inet_aton(row[0], &addr);
			memcpy(&return_ip, &addr.s_addr, 4);
		}
		
		/* Release memory used to store results and close connection */
		mysql_free_result(res);
	}

	mysql_close(conn);
	
	return return_ip;

}

/* Check to see if an ip is reserved as a static ip */
uint32_t reservedIp(struct static_lease *lease_struct, uint32_t ip)
{
	uint32_t return_val = 0;
	char query[256];

	MYSQL *conn;
	MYSQL_RES *res;
	MYSQL_ROW row;

	(void) lease_struct;

	conn = mysql_init(NULL);

	/* Connect to database */
	if (!mysql_real_connect(conn, server_config.dbserver, server_config.user, server_config.password, server_config.database, 0, NULL, 0)) {
		fprintf(stderr, "%s\n", mysql_error(conn));
	}
	
	if (server_config.table_efficient)
		snprintf(query, 256, "SELECT TRUE FROM %s WHERE ip = %u LIMIT 1", server_config.table_staticleases, ip);
	else
		snprintf(query, 256, "SELECT TRUE FROM %s WHERE ip = INET_NTOA(%u) LIMIT 1", server_config.table_staticleases, ip);
#ifdef UDHCP_DEBUG
	printf("%s\n", query);
#endif
	

	/* send SQL query */
	if (mysql_query(conn, query)) {
		fprintf(stderr, "%s\n", mysql_error(conn));
		return_val = 0;
	} else {
		res = mysql_use_result(conn);
		
		/* Should be only one row, otherwise take the last I guess ;) */
		while ((row = mysql_fetch_row(res)) != NULL) {
			return_val = 1;
		}
		
		/* Release memory used to store results and close connection */
		mysql_free_result(res);
	}

	mysql_close(conn);

	return return_val;

}

#ifdef UDHCP_DEBUG
/* Print out static leases just to check what's going on */
/* Takes the address of the pointer to the static_leases linked list */
void printStaticLeases(struct static_lease **arg)
{
	char query[256];

	(void) arg;
	
	MYSQL *conn;
	MYSQL_RES *res;
	MYSQL_ROW row;

	conn = mysql_init(NULL);

	/* Connect to database */
	if (!mysql_real_connect(conn, server_config.dbserver, server_config.user, server_config.password, server_config.database, 0, NULL, 0)) {
		fprintf(stderr, "%s\n", mysql_error(conn));
		exit(0);
	}
	
	if (server_config.table_efficient)
		snprintf(query, 256, "SELECT mac, INET_NTOA(ip) FROM %s", server_config.table_staticleases);
	else
		snprintf(query, 256, "SELECT mac, ip FROM %s", server_config.table_staticleases);

	/* send SQL query */
	if (mysql_query(conn, query)) {
		fprintf(stderr, "%s\n", mysql_error(conn));
	} else {
		res = mysql_use_result(conn);
		
		/* Should be only one row, otherwise take the last I guess ;) */
		while ((row = mysql_fetch_row(res)) != NULL) {
			printf("PrintStaticLeases: Lease mac Value: %s\n", (char *)row[0]);
			printf("PrintStaticLeases: Lease ip Value: %s\n", (char *)row[1]);
		}
		
		/* Release memory used to store results and close connection */
		mysql_free_result(res);
	}

	mysql_close(conn);
}
#endif



