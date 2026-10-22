#ifndef NIGHTWIRE_ROUTE_DUMP_H
#define NIGHTWIRE_ROUTE_DUMP_H

#include <stdint.h>

typedef struct nw_route_record {
    char destination[48];
    char gateway[48];
    char mac[32];
    char ifname[16];
    int32_t is_default;
    int32_t is_neighbor;
} nw_route_record;

/// Copies IPv4 default routes and ARP neighbors into `out`.
/// Returns the number of records, or -1 when the routing table cannot be read.
int nw_copy_routes(nw_route_record *out, int capacity);

/// Writes system resolver addresses into consecutive 48-byte slots.
/// Returns the number of addresses, or -1 when the resolver cannot be read.
int nw_copy_dns(char *buffer, int capacity);

typedef struct nw_media_info {
    int32_t valid;
    int32_t type;
    int32_t subtype;
    int32_t status;
} nw_media_info;

/// Reads the active link media. `valid` is 0 when the interface has no media ioctl.
nw_media_info nw_read_media(const char *ifname);

#endif
