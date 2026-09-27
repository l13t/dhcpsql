#include <assert.h>
#include <stdint.h>
#include <string.h>
#include <stdlib.h>
#include "udhcp/dhcpd.h"
#include "udhcp/options.h"

int main(void)
{
    struct dhcpMessage *p = calloc(1, sizeof(*p));
    /* A code at the last byte must not read a length beyond the packet. */
    p->options[307] = DHCP_MESSAGE_TYPE;
    assert(get_option(p, DHCP_MESSAGE_TYPE) == NULL);
    assert(get_option(p, DHCP_SERVER_ID) == NULL);
    memset(p, 0, sizeof(*p));
    p->options[0] = DHCP_LEASE_TIME;
    p->options[1] = 1;
    p->options[2] = 60;
    p->options[3] = DHCP_END;
    assert(get_option(p, DHCP_LEASE_TIME) == NULL);
    p->options[1] = 0;
    assert(get_option(p, DHCP_LEASE_TIME) == NULL);
    /* Overload can select sname alone, or file followed by sname. */
    for (int over = 1; over <= 3; over++) {
        memset(p, 0, sizeof(*p));
        uint8_t opts[] = {DHCP_MESSAGE_TYPE, 1, DHCPDISCOVER,
                         DHCP_OPTION_OVER, 1, over, DHCP_END};
        memcpy(p->options, opts, sizeof(opts));
        p->file[0] = DHCP_END;
        p->sname[0] = DHCP_END;
        uint8_t *field = over == 1 ? p->file : p->sname;
        uint8_t lease[] = {DHCP_LEASE_TIME, 4, 0, 0, 0, 60, DHCP_END};
        memcpy(field, lease, sizeof(lease));
        assert(get_option(p, DHCP_LEASE_TIME) == field + 2);
    }
#ifdef DHCPsql
    memset(p, 0, sizeof(*p));
    p->options[0] = DHCP_END;
    char *ttl[] = {"23", "64", NULL};
    assert(add_option_row(p->options, ttl));
    assert(*get_option(p, 23) == 64);
    char *bad[] = {"23", "256", NULL};
    assert(!add_option_row(p->options, bad));
    bad[1] = "-1";
    assert(!add_option_row(p->options, bad));
    bad[1] = "garbage";
    assert(!add_option_row(p->options, bad));
    bad[1] = NULL;
    assert(!add_option_row(p->options, bad));
    char *dns[] = {"6", "8.8.8.8 1.1.1.1", NULL};
    assert(add_option_row(p->options, dns));
    assert(get_option(p, 6)[-1] == 8);
    assert(!strcmp(dns[1], "8.8.8.8 1.1.1.1"));
#endif
    /* Exercise all remaining-length boundaries with malformed TLVs. */
    for (int offset = 0; offset < 308; offset++) {
        for (int len = 0; len < 256; len++) {
            memset(p, 0, sizeof(*p));
            p->options[offset] = DHCP_LEASE_TIME;
            if (offset + 1 < 308) p->options[offset + 1] = len;
            uint8_t *found = get_option(p, DHCP_LEASE_TIME);
            assert((found != NULL) == (len == 4 && offset + 6 <= 308));
        }
    }
    free(p);
    return 0;
}
