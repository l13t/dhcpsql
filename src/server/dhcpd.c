/* dhcpd.c
 *
 * udhcp Server
 * Copyright (C) 1999 Matthew Ramsay <matthewr@moreton.com.au>
 *			Chris Trew <ctrew@moreton.com.au>
 *
 * Rewrite by Russ Dill <Russ.Dill@asu.edu> July 2001
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

#include <fcntl.h>
#include <string.h>
#include <stdlib.h>
#include <sys/wait.h>
#include <arpa/inet.h>
#include <netdb.h>
#include <netinet/in.h>
#include <sys/socket.h>
#include <unistd.h>
#include <signal.h>
#include <errno.h>
#include <sys/ioctl.h>
#include <time.h>
#include <sys/time.h>
#include <getopt.h>

#include "udhcp/dhcpd.h"
#include "udhcp/arpping.h"
#include "udhcp/socket.h"
#include "udhcp/options.h"
#include "udhcp/files.h"
#include "udhcp/serverpacket.h"
#include "udhcp/common.h"
#include "udhcp/signalpipe.h"
#include "udhcp/static_leases.h"
#include "udhcp/version.h"


/* globals */
struct dhcpOfferedAddr *leases;
struct server_config_t server_config;

#ifndef COMBINED_BINARY
static void __attribute__ ((noreturn)) show_usage(void)
{
	printf(
"Usage: udhcpd [OPTIONS] [CONFIGFILE]\n\n"
"udhcp server (udhcpd) " VERSION "\n\n"
"  -f, --foreground                Run in foreground\n"
"  -S, --syslog                    Log to syslog too\n"
"  -h, --help                      Display this help and exit\n"
"  -v, --version                   Display version information and exit\n\n"
"Arguments:\n"
"  CONFIGFILE                      Configuration file to use\n"
"                                  (default: " DHCPD_CONF_FILE ")\n\n"
#ifdef DHCPsql
"This version was compiled with MySQL support.\n"
#endif
	);
	exit(0);
}

static void __attribute__ ((noreturn)) show_version(void)
{
	printf("udhcpd " VERSION "\n");
	exit(0);
}
#else
/* Combined binary mode - simpler help */
static void __attribute__ ((noreturn)) show_usage(void)
{
	printf(
"Usage: udhcpd [CONFIGFILE]\n\n"
"udhcp server " VERSION "\n\n"
"Arguments:\n"
"  CONFIGFILE                      Configuration file to use\n"
"                                  (default: " DHCPD_CONF_FILE ")\n\n"
"Options:\n"
"  --help, -h                      Display this help and exit\n"
"  --version, -v                   Display version information and exit\n\n"
#ifdef DHCPsql
"This version was compiled with MySQL support.\n"
#endif
	);
	exit(0);
}

static void __attribute__ ((noreturn)) show_version(void)
{
	printf("udhcpd " VERSION "\n");
	exit(0);
}
#endif


#ifdef COMBINED_BINARY
int udhcpd_main(int argc, char *argv[])
#else
int main(int argc, char *argv[])
#endif
{
	fd_set rfds;
	struct timeval tv;
	int server_socket = -1;
	int bytes, retval;
	struct dhcpMessage packet;
	uint8_t *state;
	uint8_t *server_id, *requested;
	uint32_t server_id_align, requested_align;
	unsigned long timeout_end;
	struct option_set *option;
	struct dhcpOfferedAddr *lease;
	struct dhcpOfferedAddr static_lease;
	int max_sock;
	unsigned long num_ips;
	uint32_t static_lease_ip;
	char *config_file = DHCPD_CONF_FILE;
	
#ifndef COMBINED_BINARY
	int foreground = 0;
	int opt;
#endif
	
#ifndef COMBINED_BINARY
	/* Parse command line options */
	static struct option long_options[] = {
		{"foreground", no_argument, 0, 'f'},
		{"syslog", no_argument, 0, 'S'},
		{"help", no_argument, 0, 'h'},
		{"version", no_argument, 0, 'v'},
		{0, 0, 0, 0}
	};

	while ((opt = getopt_long(argc, argv, "fShv", long_options, NULL)) != -1) {
		switch (opt) {
		case 'f':
			foreground = 1;
			break;
		case 'S':
			/* syslog option - handled in logging */
			break;
		case 'h':
			show_usage();
			break;
		case 'v':
			show_version();
			break;
		default:
			show_usage();
		}
	}
	
	/* Get config file from remaining arguments */
	if (optind < argc) {
		config_file = argv[optind];
	}
#else
	/* Combined binary mode - keep simple parsing for compatibility */
	if (argc >= 2) {
		if (strcmp(argv[1], "--help") == 0 || strcmp(argv[1], "-h") == 0) {
			show_usage();
		}
		if (strcmp(argv[1], "--version") == 0 || strcmp(argv[1], "-v") == 0) {
			show_version();
		}
		config_file = argv[1];
	}
#endif

	memset(&server_config, 0, sizeof(struct server_config_t));
	read_config(config_file);

	/* Start the log, sanitize fd's, and write a pid file */
	start_log_and_pid("udhcpd", server_config.pidfile);

	if ((option = find_option(server_config.options, DHCP_LEASE_TIME))) {
		memcpy(&server_config.lease, option->data + 2, 4);
		server_config.lease = ntohl(server_config.lease);
	}
	else server_config.lease = LEASE_TIME;

	/* Sanity check */
	num_ips = ntohl(server_config.end) - ntohl(server_config.start);
	if (server_config.max_leases > num_ips) {
		LOG(LOG_ERR, "max_leases value (%lu) not sane, "
			"setting to %lu instead",
			server_config.max_leases, num_ips);
		server_config.max_leases = num_ips;
	}

	leases = xcalloc(server_config.max_leases, sizeof(struct dhcpOfferedAddr));
	read_leases(server_config.lease_file);

	if (read_interface(server_config.interface, &server_config.ifindex,
			   &server_config.server, server_config.arp) < 0)
		return 1;

#ifndef UDHCP_DEBUG
	background(server_config.pidfile); /* hold lock during fork. */
#endif

	/* Setup the signal pipe */
	udhcp_sp_setup();

	timeout_end = time(0) + server_config.auto_time;
	while(1) { /* loop until universe collapses */

		if (server_socket < 0)
			if ((server_socket = listen_socket(INADDR_ANY, SERVER_PORT, server_config.interface)) < 0) {
				LOG(LOG_ERR, "FATAL: couldn't create server socket, %m");
				return 2;
			}

		max_sock = udhcp_sp_fd_set(&rfds, server_socket);
		if (server_config.auto_time) {
			tv.tv_sec = timeout_end - time(0);
			tv.tv_usec = 0;
		}
		if (!server_config.auto_time || tv.tv_sec > 0) {
			retval = select(max_sock + 1, &rfds, NULL, NULL,
					server_config.auto_time ? &tv : NULL);
		} else retval = 0; /* If we already timed out, fall through */

		if (retval == 0) {
			write_leases();
			timeout_end = time(0) + server_config.auto_time;
			continue;
		} else if (retval < 0 && errno != EINTR) {
			DEBUG(LOG_INFO, "error on select");
			continue;
		}

		switch (udhcp_sp_read(&rfds)) {
		case SIGUSR1:
			LOG(LOG_INFO, "Received a SIGUSR1");
			write_leases();
			/* why not just reset the timeout, eh */
			timeout_end = time(0) + server_config.auto_time;
			continue;
		case SIGTERM:
			LOG(LOG_INFO, "Received a SIGTERM");
			return 0;
		case 0: break;		/* no signal */
		default: continue;	/* signal or error (probably EINTR) */
		}

		if ((bytes = get_packet(&packet, server_socket)) < 0) { /* this waits for a packet - idle */
			if (bytes == -1 && errno != EINTR) {
				DEBUG(LOG_INFO, "error on read, %m, reopening socket");
				close(server_socket);
				server_socket = -1;
			}
			continue;
		}

		if ((state = get_option(&packet, DHCP_MESSAGE_TYPE)) == NULL) {
			DEBUG(LOG_ERR, "couldn't get option from packet, ignoring");
			continue;
		}

		/* Look for a static lease */
		static_lease_ip = getIpByMac(server_config.static_leases, &packet.chaddr);

		if(static_lease_ip)
		{
			printf("Found static lease: %x\n", static_lease_ip);

			memcpy(&static_lease.chaddr, &packet.chaddr, 16);
			static_lease.yiaddr = static_lease_ip;
			static_lease.expires = 0;

			lease = &static_lease;

		}
		else
		{
		lease = find_lease_by_chaddr(packet.chaddr);
		}

		switch (state[0]) {
		case DHCPDISCOVER:
			DEBUG(LOG_INFO,"received DISCOVER");

			if (sendOffer(&packet) < 0) {
				LOG(LOG_ERR, "send OFFER failed");
			}
			break;
 		case DHCPREQUEST:
			DEBUG(LOG_INFO, "received REQUEST");

			requested = get_option(&packet, DHCP_REQUESTED_IP);
			server_id = get_option(&packet, DHCP_SERVER_ID);

			if (requested) memcpy(&requested_align, requested, 4);
			if (server_id) memcpy(&server_id_align, server_id, 4);

			if (lease) {
				if (server_id) {
					/* SELECTING State */
					DEBUG(LOG_INFO, "server_id = %08x", ntohl(server_id_align));
					if (server_id_align == server_config.server && requested &&
					    requested_align == lease->yiaddr) {
						sendACK(&packet, lease->yiaddr);
					}
				} else {
					if (requested) {
						/* INIT-REBOOT State */
						if (lease->yiaddr == requested_align)
							sendACK(&packet, lease->yiaddr);
						else sendNAK(&packet);
					} else {
						/* RENEWING or REBINDING State */
						if (lease->yiaddr == packet.ciaddr)
							sendACK(&packet, lease->yiaddr);
						else {
							/* don't know what to do!!!! */
							sendNAK(&packet);
						}
					}
				}

			/* what to do if we have no record of the client */
			} else if (server_id) {
				/* SELECTING State */

			} else if (requested) {
				/* INIT-REBOOT State */
				if ((lease = find_lease_by_yiaddr(requested_align))) {
					if (lease_expired(lease)) {
						/* probably best if we drop this lease */
						memset(lease->chaddr, 0, 16);
					/* make some contention for this address */
					} else sendNAK(&packet);
				} else if (requested_align < server_config.start ||
					   requested_align > server_config.end) {
					sendNAK(&packet);
				} /* else remain silent */

			} else {
				 /* RENEWING or REBINDING State */
			}
			break;
		case DHCPDECLINE:
			DEBUG(LOG_INFO,"received DECLINE");
			if (lease) {
				memset(lease->chaddr, 0, 16);
				lease->expires = time(0) + server_config.decline_time;
			}
			break;
		case DHCPRELEASE:
			DEBUG(LOG_INFO,"received RELEASE");
			if (lease) lease->expires = time(0);
			break;
		case DHCPINFORM:
			DEBUG(LOG_INFO,"received INFORM");
			send_inform(&packet);
			break;
		default:
			LOG(LOG_WARNING, "unsupported DHCP message (%02x) -- ignoring", state[0]);
		}
	}

	return 0;
}
