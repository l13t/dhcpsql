/* static_leases.h */
#ifndef _STATIC_LEASES_H
#define _STATIC_LEASES_H

#include <stdint.h>
#include "dhcpd.h"

/* Config file will pass static lease info to this function which will add it
 * to a data structure that can be searched later */
int addStaticLease(struct static_lease **lease_struct, uint8_t *mac, uint32_t *ip);

/* Lookup returns 0 for no reservation, or STATIC_LEASE_ERROR on failure.
 * The broadcast address cannot be assigned as a lease. */
#define STATIC_LEASE_ERROR UINT32_MAX
uint32_t getIpByMac(struct static_lease *lease_struct, void *arg);

/* Returns 0/1 for an unreserved/reserved IP, STATIC_LEASE_ERROR on failure. */
uint32_t reservedIp(struct static_lease *lease_struct, uint32_t ip);

#ifdef UDHCP_DEBUG
/* Print out static leases just to check what's going on */
void printStaticLeases(struct static_lease **lease_struct);
#endif

#endif



