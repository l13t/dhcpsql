/* serverpacket.c
 *
 * Construct and send DHCP server packets
 *
 * Russ Dill <Russ.Dill@asu.edu> July 2001
 *
 * Stefan de Konink <stefan@konink.de> Augustus 2006
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 2 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 675 Mass Ave, Cambridge, MA 02139, USA.
 */

#include <sys/socket.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <string.h>
#include <time.h>
#include <mysql.h>

#include "serverpacket.h"
#include "dhcpd.h"
#include "options.h"
#include "common.h"
#include "static_leases.h"

/* send a packet to giaddr using the kernel ip stack */
static int send_packet_to_relay(struct dhcpMessage *payload)
{
	DEBUG(LOG_INFO, "Forwarding packet to relay");

	return kernel_packet(payload, server_config.server, SERVER_PORT,
			payload->giaddr, SERVER_PORT);
}


/* send a packet to a specific arp address and ip address by creating our own ip packet */
static int send_packet_to_client(struct dhcpMessage *payload, int force_broadcast)
{
	uint8_t *chaddr;
	uint32_t ciaddr;

	if (force_broadcast) {
		DEBUG(LOG_INFO, "broadcasting packet to client (NAK)");
		ciaddr = INADDR_BROADCAST;
		chaddr = MAC_BCAST_ADDR;
	} else if (payload->ciaddr) {
		DEBUG(LOG_INFO, "unicasting packet to client ciaddr");
		ciaddr = payload->ciaddr;
		chaddr = payload->chaddr;
	} else if (ntohs(payload->flags) & BROADCAST_FLAG) {
		DEBUG(LOG_INFO, "broadcasting packet to client (requested)");
		ciaddr = INADDR_BROADCAST;
		chaddr = MAC_BCAST_ADDR;
	} else {
		DEBUG(LOG_INFO, "unicasting packet to client yiaddr");
		ciaddr = payload->yiaddr;
		chaddr = payload->chaddr;
	}
	return raw_packet(payload, server_config.server, SERVER_PORT,
			ciaddr, CLIENT_PORT, chaddr, server_config.ifindex);
}


/* send a dhcp packet, if force broadcast is set, the packet will be broadcast to the client */
static int send_packet(struct dhcpMessage *payload, int force_broadcast)
{
	int ret;

	if (payload->giaddr)
		ret = send_packet_to_relay(payload);
	else ret = send_packet_to_client(payload, force_broadcast);
	return ret;
}


static void init_packet(struct dhcpMessage *packet, struct dhcpMessage *oldpacket, char type)
{
	init_header(packet, type);
	packet->xid = oldpacket->xid;
	memcpy(packet->chaddr, oldpacket->chaddr, 16);
	packet->flags = oldpacket->flags;
	packet->giaddr = oldpacket->giaddr;
	packet->ciaddr = oldpacket->ciaddr;
	add_simple_option(packet->options, DHCP_SERVER_ID, server_config.server);
}


/* add in the bootp options */
static void add_bootp_options(struct dhcpMessage *packet)
{
	packet->siaddr = server_config.siaddr;
	if (server_config.sname)
		strncpy(packet->sname, server_config.sname, sizeof(packet->sname) - 1);
	if (server_config.boot_file)
		strncpy(packet->file, server_config.boot_file, sizeof(packet->file) - 1);
}


static int add_mysql_options(struct dhcpMessage *packet, void *arg)
{
	int return_value;

	char query[512];

	uint8_t *mac = arg;

	MYSQL *conn;
	MYSQL_RES *res;
	MYSQL_ROW row;

	return_value = 0;

	conn = mysql_init(NULL);

	/* Connect to database */
	if (!mysql_real_connect(conn, server_config.dbserver, server_config.user, server_config.password, server_config.database, 0, NULL, 0)) {
		fprintf(stderr, "%s\n", mysql_error(conn));
		return 0;
        }
	if (server_config.table_efficient)
		snprintf(query, 512, "SELECT * FROM (SELECT code, data FROM %s, %s WHERE %s.class = %s.class AND mac = 0x%02x%02x%02x%02x%02x%02x UNION SELECT code, data FROM %s WHERE class = 0) AS x ORDER BY code", server_config.table_staticleases, server_config.table_options, server_config.table_staticleases, server_config.table_options, mac[0],mac[1],mac[2],mac[3],mac[4],mac[5], server_config.table_options);
	else
		snprintf(query, 512, "SELECT * FROM (SELECT code, data FROM %s, %s WHERE %s.class = %s.class AND LOWER(mac) = \"%02x%02x%02x%02x%02x%02x\" UNION SELECT code, data FROM %s WHERE class = 0) AS x ORDER BY code", server_config.table_staticleases, server_config.table_options, server_config.table_staticleases, server_config.table_options, mac[0],mac[1],mac[2],mac[3],mac[4],mac[5], server_config.table_options);
#ifdef UDHCP_DEBUG
	printf("%s\n", query);
#endif

	/* send SQL query */
	if (mysql_query(conn, query)) {
		fprintf(stderr, "%s\n", mysql_error(conn));
		return_value = 0;
        } else {
		res = mysql_use_result(conn);

		while ((row = mysql_fetch_row(res)) != NULL) {
			add_option_row(packet->options, row);
			/* iets van een wrapper functie make die controleert
			 * of het volgende regeltje de zelfde option bevat
			 * als deze optie een list mag zijn, dan appenden
			 * geen list, dan vervangen
			 * nieuwe optie, dan toevoegen*/
			return_value = 1;
		}

		mysql_free_result(res);

	}
	
	mysql_close(conn);

	return return_value;
}

/* send a DHCP OFFER to a DHCP DISCOVER */
int sendOffer(struct dhcpMessage *oldpacket)
{
	struct dhcpMessage packet;
	struct dhcpOfferedAddr *lease = NULL;
	uint32_t req_align, lease_time_align = server_config.lease;
	uint8_t *req, *lease_time;
	struct option_set *curr;
	struct in_addr addr;

	uint32_t static_lease_ip;

	init_packet(&packet, oldpacket, DHCPOFFER);

	static_lease_ip = getIpByMac(server_config.static_leases, oldpacket->chaddr);

	/* ADDME: if static, short circuit */
	if(!static_lease_ip)
	{
	/* the client is in our lease/offered table */
	if ((lease = find_lease_by_chaddr(oldpacket->chaddr))) {
		if (!lease_expired(lease))
			lease_time_align = lease->expires - time(0);
		packet.yiaddr = lease->yiaddr;

	/* Or the client has a requested ip */
	} else if ((req = get_option(oldpacket, DHCP_REQUESTED_IP)) &&

		   /* Don't look here (ugly hackish thing to do) */
		   memcpy(&req_align, req, 4) &&

		   /* and the ip is in the lease range */
		   ntohl(req_align) >= ntohl(server_config.start) &&
		   ntohl(req_align) <= ntohl(server_config.end) &&
		
			!static_lease_ip &&  /* Check that its not a static lease */
			/* and is not already taken/offered */
		   ((!(lease = find_lease_by_yiaddr(req_align)) ||
		
		   /* or its taken, but expired */ /* ADDME: or maybe in here */
		   lease_expired(lease)))) {
				packet.yiaddr = req_align; /* FIXME: oh my, is there a host using this IP? */

			/* otherwise, find a free IP */
	} else {
			/* Is it a static lease? (No, because find_address skips static lease) */
		packet.yiaddr = find_address(0);

		/* try for an expired lease */
		if (!packet.yiaddr) packet.yiaddr = find_address(1);
	}

	if(!packet.yiaddr) {
		LOG(LOG_WARNING, "no IP addresses to give -- OFFER abandoned");
		return -1;
	}

	if (!add_lease(packet.chaddr, packet.yiaddr, server_config.offer_time)) {
		LOG(LOG_WARNING, "lease pool is full -- OFFER abandoned");
		return -1;
	}

	if ((lease_time = get_option(oldpacket, DHCP_LEASE_TIME))) {
		memcpy(&lease_time_align, lease_time, 4);
		lease_time_align = ntohl(lease_time_align);
		if (lease_time_align > server_config.lease)
			lease_time_align = server_config.lease;
	}

	/* Make sure we aren't just using the lease time from the previous offer */
	if (lease_time_align < server_config.min_lease)
		lease_time_align = server_config.lease;
	}
	/* ADDME: end of short circuit */
	else
	{
		/* It is a static lease... use it */
		packet.yiaddr = static_lease_ip;
	}


	add_simple_option(packet.options, DHCP_LEASE_TIME, htonl(lease_time_align));
	
	if (!add_mysql_options(&packet, oldpacket->chaddr)) {
	
		curr = server_config.options;
		while (curr) {
			if (curr->data[OPT_CODE] != DHCP_LEASE_TIME)
				add_option_string(packet.options, curr->data);
			curr = curr->next;
		}

		add_bootp_options(&packet);
	}

	addr.s_addr = packet.yiaddr;
	LOG(LOG_INFO, "sending OFFER of %s", inet_ntoa(addr));
	return send_packet(&packet, 0);
}


int sendNAK(struct dhcpMessage *oldpacket)
{
	struct dhcpMessage packet;

	init_packet(&packet, oldpacket, DHCPNAK);

	DEBUG(LOG_INFO, "sending NAK");
	return send_packet(&packet, 1);
}


int sendACK(struct dhcpMessage *oldpacket, uint32_t yiaddr)
{
	struct dhcpMessage packet;
	struct option_set *curr;
	uint8_t *lease_time;
	uint32_t lease_time_align = server_config.lease;
	struct in_addr addr;

	init_packet(&packet, oldpacket, DHCPACK);
	packet.yiaddr = yiaddr;

	if ((lease_time = get_option(oldpacket, DHCP_LEASE_TIME))) {
		memcpy(&lease_time_align, lease_time, 4);
		lease_time_align = ntohl(lease_time_align);
		if (lease_time_align > server_config.lease)
			lease_time_align = server_config.lease;
		else if (lease_time_align < server_config.min_lease)
			lease_time_align = server_config.lease;
	}


	if (!add_mysql_options(&packet, oldpacket->chaddr)) {
		add_simple_option(packet.options, DHCP_LEASE_TIME, htonl(lease_time_align));

		curr = server_config.options;
		while (curr) {
			if (curr->data[OPT_CODE] != DHCP_LEASE_TIME)
				add_option_string(packet.options, curr->data);
			curr = curr->next;
		}

		add_bootp_options(&packet);
	}

	addr.s_addr = packet.yiaddr;
	LOG(LOG_INFO, "sending ACK to %s", inet_ntoa(addr));

	if (send_packet(&packet, 0) < 0)
		return -1;

	add_lease(packet.chaddr, packet.yiaddr, lease_time_align);

	return 0;
}


int send_inform(struct dhcpMessage *oldpacket)
{
	struct dhcpMessage packet;
	struct option_set *curr;

	init_packet(&packet, oldpacket, DHCPACK);

	curr = server_config.options;
	while (curr) {
		if (curr->data[OPT_CODE] != DHCP_LEASE_TIME)
			add_option_string(packet.options, curr->data);
		curr = curr->next;
	}

	add_bootp_options(&packet);

	return send_packet(&packet, 0);
}
