#ifndef MANXIA_TRANSFER_RTC_MBEDTLS_CONFIG_H
#define MANXIA_TRANSFER_RTC_MBEDTLS_CONFIG_H

/*
 * WebRTC DTLS transport needs RFC 5764 DTLS-SRTP negotiation.
 * The WebDAV mbedTLS build keeps this disabled, so Transfer RTC builds
 * its own mbedTLS binaries with this user config enabled.
 */
#define MBEDTLS_SSL_DTLS_SRTP

#endif
