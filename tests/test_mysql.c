#include <assert.h>
#include <stdint.h>
#include <string.h>
#include <stdlib.h>
#include <time.h>
#include <arpa/inet.h>
#include "udhcp/dhcpd.h"
#include "udhcp/options.h"
#include "udhcp/leases.h"
#include "udhcp/serverpacket.h"
#include "udhcp/static_leases.h"
#include "udhcp/arpping.h"

struct server_config_t server_config;
struct dhcpOfferedAddr *leases;
static MYSQL connection;
static MYSQL_RES result;
static int unavailable, query_error, result_error, open_connections;
static int cursor, query_kind, has_reservation, mac_reserved, options_mode, packets_sent;
static char last_query[2048];
static struct dhcpMessage sent;

MYSQL *mysql_init(MYSQL *arg) { (void)arg; open_connections++; return &connection; }
int mysql_options(MYSQL *c, enum mysql_option o, const void *v)
{ (void)c; (void)o; (void)v; return 0; }
MYSQL *mysql_real_connect(MYSQL *c, const char *h, const char *u, const char *p,
    const char *d, unsigned int port, const char *s, unsigned long flags)
{
    (void)h; (void)u; (void)p; (void)d; (void)port; (void)s; (void)flags;
    return unavailable ? NULL : c;
}
void mysql_close(MYSQL *c) { (void)c; open_connections--; }
const char *mysql_error(MYSQL *c) { (void)c; return "simulated error"; }
unsigned int mysql_errno(MYSQL *c) { (void)c; return 0; }
int mysql_query(MYSQL *c, const char *query)
{
    (void)c;
    assert(strlen(query) < sizeof(last_query));
    strcpy(last_query, query);
    cursor = 0;
    query_kind = strstr(query, "priority") ? 1 : 0;
    return query_error;
}
MYSQL_RES *mysql_store_result(MYSQL *c) { (void)c; return result_error ? NULL : &result; }
MYSQL_ROW mysql_fetch_row(MYSQL_RES *r)
{
    static char *address[] = {"192.168.1.100", NULL};
    static char *dns[] = {"6", "8.8.8.8", "0", NULL};
    static char *default_lease[] = {"51", "7200", "0", NULL};
    static char *class_lease[] = {"51", "86400", "1", NULL};
    (void)r;
    if (!query_kind) return mac_reserved && cursor++ == 0 ? address : NULL;
    if (cursor++ == 0) return dns;
    if (options_mode && cursor == 2) return default_lease;
    if (options_mode == 2 && cursor == 3) return class_lease;
    return NULL;
}
void mysql_free_result(MYSQL_RES *r) { (void)r; }
unsigned long long mysql_num_rows(MYSQL_RES *r) { (void)r; return has_reservation; }

void init_header(struct dhcpMessage *p, char type)
{
    memset(p, 0, sizeof(*p));
    p->options[0] = DHCP_END;
    add_simple_option(p->options, DHCP_MESSAGE_TYPE, type);
}
int kernel_packet(struct dhcpMessage *p, uint32_t src, int sport, uint32_t dst, int dport)
{
    (void)src; (void)sport; (void)dst; (void)dport;
    sent = *p; packets_sent++; return 0;
}
int raw_packet(struct dhcpMessage *p, uint32_t src, int sport, uint32_t dst,
    int dport, uint8_t *arp, int index)
{
    (void)arp; (void)index;
    return kernel_packet(p, src, sport, dst, dport);
}
int arpping(uint32_t ip, uint32_t src, uint8_t *arp, char *iface)
{ (void)ip; (void)src; (void)arp; (void)iface; return 1; }

static uint32_t sent_lease(void)
{
    uint32_t value;
    uint8_t *option = get_option(&sent, DHCP_LEASE_TIME);
    assert(option && option[-1] == 4);
    memcpy(&value, option, 4);
    int count = 0;
    for (int i = 0; sent.options[i] != DHCP_END; i += sent.options[i + 1] + 2)
        if (sent.options[i] == DHCP_LEASE_TIME) count++;
    assert(count == 1);
    return ntohl(value);
}

int main(void)
{
    uint8_t mac[16] = {0, 17, 34, 51, 68, 85};
    uint32_t ip = inet_addr("192.168.1.100");
    server_config.table_staticleases = "staticleases";
    server_config.table_options = "options";
    server_config.lease = 3600;
    server_config.min_lease = 60;
    server_config.offer_time = 60;
    server_config.max_leases = 4;
    server_config.start = ip;
    server_config.end = ip;
    leases = calloc(server_config.max_leases, sizeof(*leases));
    for (int efficient = 0; efficient <= 1; efficient++) {
        server_config.table_efficient = efficient;
        has_reservation = mac_reserved = 1;
        assert(addStaticLease(NULL, mac, &ip));
        assert(strstr(last_query, "3232235876"));
        assert(reservedIp(NULL, ip));
        assert(strstr(last_query, "3232235876"));
        assert(getIpByMac(NULL, mac) == ip);
        has_reservation = mac_reserved = 0;
        assert(!reservedIp(NULL, ip));
        assert(getIpByMac(NULL, mac) == 0);
    }
    struct dhcpMessage request;
    init_header(&request, DHCPREQUEST);
    memcpy(request.chaddr, mac, 16);
    for (options_mode = 0; options_mode <= 2; options_mode++) {
        uint32_t expected = options_mode == 0 ? 3600 : options_mode == 1 ? 7200 : 86400;
        time_t before = time(NULL);
        assert(sendACK(&request, ip) == 0);
        assert(sent_lease() == expected);
        struct dhcpOfferedAddr *lease = find_lease_by_chaddr(mac);
        assert(lease && lease->expires >= (unsigned long)before + expected);
        assert(lease->expires <= (unsigned long)time(NULL) + expected);
    }
    options_mode = 2;
    add_simple_option(request.options, DHCP_LEASE_TIME, htonl(600));
    assert(sendACK(&request, ip) == 0);
    assert(sent_lease() == 600);
    assert(find_lease_by_chaddr(mac)->expires <= (unsigned long)time(NULL) + 600);
    has_reservation = mac_reserved = 1;
    assert(sendOffer(&request) == 0);
    assert(sent_lease() == 600);
    /* No process exit, no connection leaks and no offers on lookup failure. */
    for (int failure = 0; failure < 3; failure++) {
        unavailable = failure == 0;
        query_error = failure == 1;
        result_error = failure == 2;
        int before = packets_sent;
        assert(getIpByMac(NULL, mac) == STATIC_LEASE_ERROR);
        assert(reservedIp(NULL, ip) == STATIC_LEASE_ERROR);
        assert(find_address(0) == 0);
        assert(sendOffer(&request) == -1);
        assert(sendACK(&request, ip) == -1);
        assert(packets_sent == before);
        assert(open_connections == 0);
    }
    unavailable = query_error = result_error = 0;
    assert(sendACK(&request, ip) == 0);
    assert(open_connections == 0);
    /* A requested address cannot bypass an offline client's reservation. */
    memset(leases, 0, server_config.max_leases * sizeof(*leases));
    init_header(&request, DHCPDISCOVER);
    memcpy(request.chaddr, mac, 16);
    add_simple_option(request.options, DHCP_REQUESTED_IP, ip);
    mac_reserved = 0;
    int before = packets_sent;
    assert(sendOffer(&request) == -1);
    assert(packets_sent == before);
    mac_reserved = 1;
    assert(sendOffer(&request) == 0);
    assert(sent.yiaddr == ip);
    free(leases);
    return 0;
}
