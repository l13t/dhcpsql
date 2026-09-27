/*
 * options.c -- DHCP server option packet tools
 * Rewrite by Russ Dill <Russ.Dill@asu.edu> July 2001
 */

#include <stdlib.h>
#include <string.h>
#include <errno.h>
#include <limits.h>
#include <stdint.h>

#include "udhcp/dhcpd.h"
#include "udhcp/files.h"
#include "udhcp/options.h"
#include "udhcp/common.h"

#ifdef DHCPsql
#include <mysql.h>
#include <arpa/inet.h>
#endif

/* supported options are easily added here */
struct dhcp_option dhcp_options[] = {
	/* name[10]	flags					code */
	{"subnet",	OPTION_IP | OPTION_REQ,			0x01},
	{"timezone",	OPTION_S32,				0x02},
	{"router",	OPTION_IP | OPTION_LIST | OPTION_REQ,	0x03},
	{"timesvr",	OPTION_IP | OPTION_LIST,		0x04},
	{"namesvr",	OPTION_IP | OPTION_LIST,		0x05},
	{"dns",		OPTION_IP | OPTION_LIST | OPTION_REQ,	0x06},
	{"logsvr",	OPTION_IP | OPTION_LIST,		0x07},
	{"cookiesvr",	OPTION_IP | OPTION_LIST,		0x08},
	{"lprsvr",	OPTION_IP | OPTION_LIST,		0x09},
	{"hostname",	OPTION_STRING | OPTION_REQ,		0x0c},
	{"bootsize",	OPTION_U16,				0x0d},
	{"domain",	OPTION_STRING | OPTION_REQ,		0x0f},
	{"swapsvr",	OPTION_IP,				0x10},
	{"rootpath",	OPTION_STRING,				0x11},
	{"ipttl",	OPTION_U8,				0x17},
	{"mtu",		OPTION_U16,				0x1a},
	{"broadcast",	OPTION_IP | OPTION_REQ,			0x1c},
	{"nisdomain",	OPTION_STRING | OPTION_REQ,		0x28},
	{"nissrv",	OPTION_IP | OPTION_LIST | OPTION_REQ,	0x29},
	{"ntpsrv",	OPTION_IP | OPTION_LIST | OPTION_REQ,	0x2a},
	{"wins",	OPTION_IP | OPTION_LIST,		0x2c},
	{"requestip",	OPTION_IP,				0x32},
	{"lease",	OPTION_U32,				0x33},
	{"dhcptype",	OPTION_U8,				0x35},
	{"serverid",	OPTION_IP,				0x36},
	{"message",	OPTION_STRING,				0x38},
	{"tftp",	OPTION_STRING,				0x42},
	{"bootfile",	OPTION_STRING,				0x43},
	{"",		0x00,				0x00}
};

/* Lengths of the different option types */
int option_lengths[] = {
	[OPTION_IP] =		4,
	[OPTION_IP_PAIR] =	8,
	[OPTION_BOOLEAN] =	1,
	[OPTION_STRING] =	1,
	[OPTION_U8] =		1,
	[OPTION_U16] =		2,
	[OPTION_S16] =		2,
	[OPTION_U32] =		4,
	[OPTION_S32] =		4
};


/* get an option with bounds checking (warning, not aligned). */
uint8_t *get_option(struct dhcpMessage *packet, int code)
{
	int i = 0, length = sizeof(packet->options);
	uint8_t *optionptr = packet->options;
	int over = 0, curr = OPTION_FIELD;

	while (i < length) {
		int opt = optionptr[i];
		int len, j;
		if (opt == DHCP_PADDING) { i++; continue; }
		if (opt == DHCP_END) {
			if (curr == OPTION_FIELD && (over & FILE_FIELD)) {
				optionptr = packet->file; length = sizeof(packet->file);
				curr = FILE_FIELD;
			} else if (curr != SNAME_FIELD && (over & SNAME_FIELD)) {
				optionptr = packet->sname; length = sizeof(packet->sname);
				curr = SNAME_FIELD;
			} else break;
			i = 0;
			continue;
		}
		if (length - i < 2) return NULL;
		len = optionptr[i + OPT_LEN];
		if (!len || len > length - i - 2) return NULL;
		if (opt == DHCP_OPTION_OVER) {
			if (len != 1) return NULL;
			if (curr == OPTION_FIELD) over = optionptr[i + 2];
		}
		if (opt == code) {
			/* Callers copy fixed-size values without another length check. */
			for (j = 0; dhcp_options[j].code; j++) {
				int type = dhcp_options[j].flags & TYPE_MASK;
				int size = option_lengths[type];
				if (dhcp_options[j].code == code && type != OPTION_STRING &&
				    (len < size || len % size ||
				     (!(dhcp_options[j].flags & OPTION_LIST) && len != size)))
					return NULL;
			}
			return optionptr + i + 2;
		}
		i += len + 2;
	}
	return NULL;
}


/* return the position of the 'end' option (no bounds checking) */
int end_option(uint8_t *optionptr)
{
	int i = 0;

	while (optionptr[i] != DHCP_END) {
		if (optionptr[i] == DHCP_PADDING) i++;
		else i += optionptr[i + OPT_LEN] + 2;
	}
	return i;
}


/* add an option string to the options (an option string contains an option code,
 * length, then data) */
int add_option_string(uint8_t *optionptr, uint8_t *string)
{
	int end = end_option(optionptr);

	/* end position + string length + option code/length + end option */
	if (end + string[OPT_LEN] + 2 + 1 >= 308) {
		LOG(LOG_ERR, "Option 0x%02x did not fit into the packet!", string[OPT_CODE]);
		return 0;
	}
	DEBUG(LOG_INFO, "adding option 0x%02x", string[OPT_CODE]);
	memcpy(optionptr + end, string, string[OPT_LEN] + 2);
	optionptr[end + string[OPT_LEN] + 2] = DHCP_END;
	return string[OPT_LEN] + 2;
}

#ifdef DHCPsql
int add_option_row(uint8_t *optionptr, MYSQL_ROW row)
{
	char *endptr;
	uint8_t option[257] = {0};
	unsigned long value;
	long signed_value;
	uint16_t u16;
	uint32_t u32;
	int i, flags = 0, length = 0, type;
	struct in_addr addr;

	if (!row || !row[0] || !row[1]) return 0;
	errno = 0;
	value = strtoul(row[0], &endptr, 10);
	if (errno || endptr == row[0] || *endptr || !value || value >= DHCP_END) return 0;
	for (i = 0; dhcp_options[i].code; i++) {
		if (dhcp_options[i].code == value) {
			flags = dhcp_options[i].flags;
			length = option_lengths[flags & TYPE_MASK];
			break;
		}
	}
	if (!length) return 0;
	option[OPT_CODE] = value;
	type = flags & TYPE_MASK;
	if (type == OPTION_IP) {
		if (flags & OPTION_LIST) {
			char copy[256], *save, *ip;
			if (strlen(row[1]) >= sizeof(copy)) return 0;
			strcpy(copy, row[1]);
			length = 0;
			for (ip = strtok_r(copy, " ", &save); ip; ip = strtok_r(NULL, " ", &save)) {
				if (length + 4 > 255 || !inet_aton(ip, &addr)) return 0;
				memcpy(option + 2 + length, &addr.s_addr, 4);
				length += 4;
			}
			if (!length) return 0;
		} else {
			if (!inet_aton(row[1], &addr)) return 0;
			memcpy(option + 2, &addr.s_addr, 4);
		}
	} else if (type == OPTION_STRING) {
		length = strlen(row[1]);
		if (!length || length > 255) return 0;
		memcpy(option + 2, row[1], length);
	} else {
		errno = 0;
		if (type == OPTION_S16 || type == OPTION_S32) {
			signed_value = strtol(row[1], &endptr, 0);
			if (errno || endptr == row[1] || *endptr ||
			    signed_value < (type == OPTION_S16 ? INT16_MIN : INT32_MIN) ||
			    signed_value > (type == OPTION_S16 ? INT16_MAX : INT32_MAX)) return 0;
			value = signed_value;
		} else {
			value = strtoul(row[1], &endptr, 0);
			if (errno || endptr == row[1] || *endptr || row[1][0] == '-' ||
			    value > (length == 1 ? UINT8_MAX : length == 2 ? UINT16_MAX : UINT32_MAX)) return 0;
		}
		switch (type) {
		case OPTION_BOOLEAN:
			if (value > 1) return 0;
			/* fall through */
		case OPTION_U8:
			option[2] = value;
			break;
		case OPTION_U16:
		case OPTION_S16:
			u16 = htons(value);
			memcpy(option + 2, &u16, sizeof(u16));
			break;
		case OPTION_U32:
		case OPTION_S32:
			u32 = htonl(value);
			memcpy(option + 2, &u32, sizeof(u32));
			break;
		default: return 0;
		}
	}
	option[OPT_LEN] = length;
	return add_option_string(optionptr, option);
}
#endif


/* add a one to four byte option to a packet */
int add_simple_option(uint8_t *optionptr, uint8_t code, uint32_t data)
{
	char length = 0;
	int i;
	uint8_t option[2 + 4];
	uint8_t *u8;
	uint16_t *u16;
	uint32_t *u32;
	uint32_t aligned;
	u8 = (uint8_t *) &aligned;
	u16 = (uint16_t *) &aligned;
	u32 = &aligned;

	for (i = 0; dhcp_options[i].code; i++)
		if (dhcp_options[i].code == code) {
			length = option_lengths[dhcp_options[i].flags & TYPE_MASK];
		}

	if (!length) {
		DEBUG(LOG_ERR, "Could not add option 0x%02x", code);
		return 0;
	}

	option[OPT_CODE] = code;
	option[OPT_LEN] = length;

	switch (length) {
		case 1: *u8 =  data; break;
		case 2: *u16 = data; break;
		case 4: *u32 = data; break;
	}
	memcpy(option + 2, &aligned, length);
	return add_option_string(optionptr, option);
}


/* find option 'code' in opt_list */
struct option_set *find_option(struct option_set *opt_list, char code)
{
	while (opt_list && opt_list->data[OPT_CODE] < code)
		opt_list = opt_list->next;

	if (opt_list && opt_list->data[OPT_CODE] == code) return opt_list;
	else return NULL;
}


/* add an option to the opt_list */
void attach_option(struct option_set **opt_list, struct dhcp_option *option, char *buffer, int length)
{
	struct option_set *existing, *new, **curr;

	/* add it to an existing option */
	if ((existing = find_option(*opt_list, option->code))) {
		DEBUG(LOG_INFO, "Attaching option %s to existing member of list", option->name);
		if (option->flags & OPTION_LIST) {
			if (existing->data[OPT_LEN] + length <= 255) {
				existing->data = realloc(existing->data,
						existing->data[OPT_LEN] + length + 2);
				memcpy(existing->data + existing->data[OPT_LEN] + 2, buffer, length);
				existing->data[OPT_LEN] += length;
			} /* else, ignore the data, we could put this in a second option in the future */
		} /* else, ignore the new data */
	} else {
		DEBUG(LOG_INFO, "Attaching option %s to list", option->name);

		/* make a new option */
		new = xmalloc(sizeof(struct option_set));
		new->data = xmalloc(length + 2);
		new->data[OPT_CODE] = option->code;
		new->data[OPT_LEN] = length;
		memcpy(new->data + 2, buffer, length);

		curr = opt_list;
		while (*curr && (*curr)->data[OPT_CODE] < option->code)
			curr = &(*curr)->next;

		new->next = *curr;
		*curr = new;
	}
}
