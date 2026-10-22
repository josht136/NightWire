#include "RouteDump.h"

#include <arpa/inet.h>
#include <net/if.h>
#include <netinet/in.h>
#include <resolv.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/sysctl.h>
#include <sys/types.h>
#include <unistd.h>

#if __has_include(<net/route.h>)
#include <net/route.h>
#define NW_SYSTEM_ROUTE_H 1
#endif

#if __has_include(<net/if_media.h>) && __has_include(<sys/sockio.h>)
#include <net/if_media.h>
#include <sys/ioctl.h>
#include <sys/sockio.h>
#define NW_HAS_MEDIA 1
#endif

#ifndef NET_RT_DUMP2
#define NET_RT_DUMP2 7
#endif

#ifndef RTF_UP
#define RTF_UP 0x1
#endif

#ifndef RTF_GATEWAY
#define RTF_GATEWAY 0x2
#endif

#ifndef RTAX_DST
#define RTAX_DST 0
#define RTAX_GATEWAY 1
#define RTAX_MAX 8
#endif

/*
 * iOS does not ship <net/route.h>. This layout matches Darwin's rt_msghdr2
 * (xnu bsd/net/route.h): a 36-byte prelude plus 56 bytes of rt_metrics.
 * msglen, index, flags, and addrs sit at the same offsets in rt_msghdr.
 */
#ifndef NW_SYSTEM_ROUTE_H
struct nw_rt_metrics {
    uint32_t rmx_locks;
    uint32_t rmx_mtu;
    uint32_t rmx_hopcount;
    int32_t rmx_expire;
    uint32_t rmx_recvpipe;
    uint32_t rmx_sendpipe;
    uint32_t rmx_ssthresh;
    uint32_t rmx_rtt;
    uint32_t rmx_rttvar;
    uint32_t rmx_pksent;
    uint32_t rmx_filler[4];
};

struct nw_rt_msghdr2 {
    uint16_t rtm_msglen;
    uint8_t rtm_version;
    uint8_t rtm_type;
    uint16_t rtm_index;
    int rtm_flags;
    int rtm_addrs;
    int32_t rtm_refcnt;
    int rtm_parentflags;
    int rtm_reserved;
    int rtm_use;
    uint32_t rtm_inits;
    struct nw_rt_metrics rtm_rmx;
};

_Static_assert(sizeof(struct nw_rt_msghdr2) == 92, "rt_msghdr2 layout drifted");
#define NW_RT_HDR struct nw_rt_msghdr2
#else
#define NW_RT_HDR struct rt_msghdr2
#endif

#define NW_DNS_SLOT 48

static int read_ipv4(const char *cursor, unsigned sa_len, const char *end, char *out, size_t out_len, int *is_zero) {
    if (sa_len < 8 || cursor + 8 > end || out_len == 0) {
        return 0;
    }
    uint32_t raw = 0;
    memcpy(&raw, cursor + 4, sizeof(raw));
    if (is_zero != NULL) {
        *is_zero = raw == 0;
    }
    struct in_addr address;
    memcpy(&address, &raw, sizeof(address));
    return inet_ntop(AF_INET, &address, out, (socklen_t)out_len) != NULL;
}

static void read_mac(const char *cursor, unsigned sa_len, const char *end, char *out, size_t out_len) {
    if (out_len == 0 || sa_len < 8 || cursor + 8 > end) {
        return;
    }
    unsigned nlen = (unsigned char)cursor[5];
    unsigned alen = (unsigned char)cursor[6];
    if (alen != 6 || 8u + nlen + alen > sa_len || cursor + 8u + nlen + alen > end) {
        return;
    }
    const unsigned char *mac = (const unsigned char *)cursor + 8 + nlen;
    for (int i = 0; i < 6; i++) {
        if (mac[i] != 0) {
            snprintf(
                out,
                out_len,
                "%02X:%02X:%02X:%02X:%02X:%02X",
                mac[0], mac[1], mac[2], mac[3], mac[4], mac[5]
            );
            return;
        }
    }
}

static void fill_record(const char *message, const char *message_end, int flags, int addrs, unsigned ifindex, nw_route_record *out) {
    const char *cursor = message + sizeof(NW_RT_HDR);
    char destination[48] = {0};
    char gateway[48] = {0};
    char mac[32] = {0};
    int destination_is_zero = 0;
    int have_destination = 0;
    int have_gateway = 0;

    for (int index = 0; index < RTAX_MAX; index++) {
        if ((addrs & (1 << index)) == 0) {
            continue;
        }
        if (cursor + 2 > message_end) {
            return;
        }
        unsigned sa_len = (unsigned char)cursor[0];
        unsigned sa_family = (unsigned char)cursor[1];
        size_t step = sa_len > 0 ? (1u + ((sa_len - 1u) | (sizeof(long) - 1u))) : sizeof(long);
        if (cursor + step > message_end) {
            return;
        }

        if (index == RTAX_DST && sa_len == 0) {
            have_destination = 1;
            destination_is_zero = 1;
            strlcpy(destination, "0.0.0.0", sizeof(destination));
        } else if (index == RTAX_DST && sa_family == AF_INET) {
            int is_zero = 0;
            if (read_ipv4(cursor, sa_len, message_end, destination, sizeof(destination), &is_zero)) {
                have_destination = 1;
                destination_is_zero = is_zero;
            }
        } else if (index == RTAX_GATEWAY && sa_family == AF_INET) {
            int is_zero = 0;
            if (read_ipv4(cursor, sa_len, message_end, gateway, sizeof(gateway), &is_zero) && !is_zero) {
                have_gateway = 1;
            }
        } else if (index == RTAX_GATEWAY && sa_family == AF_LINK) {
            read_mac(cursor, sa_len, message_end, mac, sizeof(mac));
        }

        cursor += step;
    }

    if (!have_destination) {
        return;
    }

    memset(out, 0, sizeof(*out));
    strlcpy(out->destination, destination, sizeof(out->destination));
    if (have_gateway) {
        strlcpy(out->gateway, gateway, sizeof(out->gateway));
    }
    if (mac[0] != '\0') {
        strlcpy(out->mac, mac, sizeof(out->mac));
    }

    char name[IF_NAMESIZE] = {0};
    if (ifindex > 0 && if_indextoname(ifindex, name) != NULL) {
        strlcpy(out->ifname, name, sizeof(out->ifname));
    }

    if (destination_is_zero && (flags & RTF_GATEWAY) && have_gateway) {
        out->is_default = 1;
    } else if (!destination_is_zero && mac[0] != '\0') {
        out->is_neighbor = 1;
    }
}

static int copy_routes_once(nw_route_record *out, int capacity) {
    int mib[6] = {CTL_NET, PF_ROUTE, 0, AF_INET, NET_RT_DUMP2, 0};
    size_t needed = 0;
    if (sysctl(mib, 6, NULL, &needed, NULL, 0) < 0 || needed == 0) {
        return -1;
    }

    size_t bytes = needed + 4096;
    char *buffer = malloc(bytes);
    if (buffer == NULL) {
        return -1;
    }
    if (sysctl(mib, 6, buffer, &bytes, NULL, 0) < 0) {
        free(buffer);
        return -1;
    }

    int count = 0;
    char *next = buffer;
    char *limit = buffer + bytes;
    while (next + sizeof(NW_RT_HDR) <= limit && count < capacity) {
        NW_RT_HDR header;
        memcpy(&header, next, sizeof(header));
        if (header.rtm_msglen < sizeof(header) || next + header.rtm_msglen > limit) {
            break;
        }
        if ((header.rtm_flags & RTF_UP) != 0) {
            nw_route_record record;
            memset(&record, 0, sizeof(record));
            fill_record(next, next + header.rtm_msglen, header.rtm_flags, header.rtm_addrs, header.rtm_index, &record);
            if (record.is_default || record.is_neighbor) {
                out[count++] = record;
            }
        }
        next += header.rtm_msglen;
    }

    free(buffer);
    return count;
}

int nw_copy_routes(nw_route_record *out, int capacity) {
    if (out == NULL || capacity <= 0) {
        return -1;
    }
    int count = copy_routes_once(out, capacity);
    if (count < 0) {
        count = copy_routes_once(out, capacity);
    }
    return count;
}

int nw_copy_dns(char *buffer, int capacity) {
    if (buffer == NULL || capacity <= 0) {
        return -1;
    }
    memset(buffer, 0, (size_t)capacity * NW_DNS_SLOT);

    struct __res_state state;
    memset(&state, 0, sizeof(state));
    if (res_ninit(&state) != 0) {
        return -1;
    }

    int written = 0;
    int limit = state.nscount;
    if (limit > MAXNS) {
        limit = MAXNS;
    }
    for (int index = 0; index < limit && written < capacity; index++) {
        char text[NW_DNS_SLOT];
        if (inet_ntop(AF_INET, &state.nsaddr_list[index].sin_addr, text, sizeof(text)) == NULL) {
            continue;
        }
        if (strcmp(text, "0.0.0.0") == 0) {
            continue;
        }
        strlcpy(buffer + written * NW_DNS_SLOT, text, NW_DNS_SLOT);
        written++;
    }

    res_ndestroy(&state);
    return written;
}

nw_media_info nw_read_media(const char *ifname) {
    nw_media_info info;
    memset(&info, 0, sizeof(info));
#if NW_HAS_MEDIA
    if (ifname == NULL || ifname[0] == '\0') {
        return info;
    }
    int fd = socket(AF_INET, SOCK_DGRAM, 0);
    if (fd < 0) {
        return info;
    }
    struct ifmediareq request;
    memset(&request, 0, sizeof(request));
    strlcpy(request.ifm_name, ifname, sizeof(request.ifm_name));
    if (ioctl(fd, SIOCGIFMEDIA, &request) == 0) {
        int word = request.ifm_active != 0 ? request.ifm_active : request.ifm_current;
        info.valid = 1;
        info.type = IFM_TYPE(word);
        info.subtype = IFM_SUBTYPE(word);
        info.status = request.ifm_status;
    }
    close(fd);
#else
    (void)ifname;
#endif
    return info;
}
