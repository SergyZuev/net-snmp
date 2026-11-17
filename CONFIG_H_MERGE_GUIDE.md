# Слияние net-snmp-config.h (5.9.4 → 5.9.5)

Файл `netsnmp/include/net-snmp/net-snmp-config.h` — ваш кастомный сгенерированный заголовок.
**Не перезаписывайте его целиком.** Внесите только перечисленные ниже точечные правки.
Все остальные ваши настройки (HAVE_*, платформенные define) остаются без изменений.

Шаблон `net-snmp-config.h.in` уже обновлён в этом пакете (лежит рядом с .h).
Используйте его как справочник при поиске мест вставки.

---

## Правка 1. Макрос NETSNMP_REQUIRE_SEMICOLON

Найдите строку:
```c
#define NETSNMP_REQUIRE_SEMICOLON extern void netsnmp_unused_function(void)
```
Замените на:
```c
#define NETSNMP_REQUIRE_SEMICOLON struct netsnmp_unused_struct
```

---

## Правка 2. Условие AES CFB128

Найдите блок (примерно в районе определения NETSNMP_USE_INTERNAL_CRYPTO / AES):
```c
#if (defined(NETSNMP_USE_OPENSSL) && defined(HAVE_OPENSSL_AES_H) && defined(HAVE_AES_CFB128_ENCRYPT)) || defined(NETSNMP_USE_INTERNAL_CRYPTO)
```
Замените на:
```c
#if (defined(NETSNMP_USE_OPENSSL) &&            \
     defined(HAVE_OPENSSL_AES_H) &&             \
     defined(HAVE_AES_CFB128_ENCRYPT) &&        \
     defined(HAVE_EVP_AES_128_CFB)) ||          \
    defined(NETSNMP_USE_INTERNAL_CRYPTO)
```

---

## Правка 3. Guard __STDC_WANT_IEC_60559_EXT__

Найдите блок с `__STDC_WANT_IEC_60559_FUNCS_EXT__` (обычно в начале секции расширений).
**Перед ним** вставьте:
```c
/* Enable extensions specified by C23 Annex F.  */
#ifndef __STDC_WANT_IEC_60559_EXT__
# undef __STDC_WANT_IEC_60559_EXT__
#endif
```

---

## Правка 4. Новые символы HAVE_*

Добавьте следующие блоки в соответствующие алфавитные позиции среди других `HAVE_*`.
Все значения — `#undef` (безопасный default: функции отсутствовали в 5.9.4, поведение не меняется).
Если ваша платформа реально поддерживает какую-то из них и вы хотите её включить — замените
`#undef` на `#define ... 1` вручную после проверки компиляции.

```c
/* Define to 1 if the 'ASN_BOOLEAN' constant is defined in an SSL header file. */
#undef HAVE_ASN_BOOLEAN

/* Define to 1 if the 'ASN_INTEGER' constant is defined in an SSL header file. */
#undef HAVE_ASN_INTEGER

/* Define to 1 if the 'ASN_OBJECT_ID' constant is defined in an SSL header file. */
#undef HAVE_ASN_OBJECT_ID

/* Define to 1 if the 'ASN_SEQUENCE' constant is defined in an SSL header file. */
#undef HAVE_ASN_SEQUENCE

/* Define to 1 if the 'ASN_SET' constant is defined in an SSL header file. */
#undef HAVE_ASN_SET

/* Define to 1 if you have the 'ERR_get_error_func' function. */
#undef HAVE_ERR_GET_ERROR_FUNC

/* Define to 1 if you have the 'EVP_aes_128_cfb' function. */
#undef HAVE_EVP_AES_128_CFB

/* Define to 1 if you have the 'getnetgrent' function. */
#undef HAVE_GETNETGRENT

/* Set if IPV6_RECVPKTINFO is usable */
#undef HAVE_IPV6_RECVPKTINFO

/* Define to 1 if you have the 'libssh2_session_handshake' function. */
#undef HAVE_LIBSSH2_SESSION_HANDSHAKE

/* Define to 1 if you have the 'malloc_trim' function. */
#undef HAVE_MALLOC_TRIM

/* Define to 1 if you have the <netgroup.h> header file. */
#undef HAVE_NETGROUP_H

/* Define to 1 if you have the <netlink/cache.h> header file. */
#undef HAVE_NETLINK_CACHE_H

/* Define to 1 if you have the <netlink/msg.h> header file. */
#undef HAVE_NETLINK_MSG_H

/* Define to 1 if you have the <netlink/route/addr.h> header file. */
#undef HAVE_NETLINK_ROUTE_ADDR_H

/* Define to 1 if you have the <netlink/route/link.h> header file. */
#undef HAVE_NETLINK_ROUTE_LINK_H

/* Define to 1 if you have the <netlink/socket.h> header file. */
#undef HAVE_NETLINK_SOCKET_H

/* Define to 1 if you have the <openssl/err.h> header file. */
#undef HAVE_OPENSSL_ERR_H

/* Define to 1 if you have the <openssl/ssl.h> header file. */
#undef HAVE_OPENSSL_SSL_H

/* Define to 1 if you have the 'SSL_CTX_set_cookie_generate_cb' function. */
#undef HAVE_SSL_CTX_SET_COOKIE_GENERATE_CB

/* Define to 1 if you have the <sys/callout.h> header file. */
#undef HAVE_SYS_CALLOUT_H

/* Define to 1 if you have the <sys/osd.h> header file. */
#undef HAVE_SYS_OSD_H

/* Define this macro if EVP_MD_CTX_init() returns void */
#undef HAVE_VOID_EVP_MD_CTX_INIT

/* Define to 1 if you have the <wolfssl/wolfcrypt/asn.h> header file. */
#undef HAVE_WOLFSSL_WOLFCRYPT_ASN_H

/* Define to 1 if you have the <wolfssl/wolfcrypt/logging.h> header file. */
#undef HAVE_WOLFSSL_WOLFCRYPT_LOGGING_H
```

---

## Правка 5. Удаление устаревшего символа

Найдите и удалите строку (если присутствует):
```c
#undef HAVE_SECURITY_CRYPTOKI_H
```
(символ удалён из upstream 5.9.5; оставленный #undef безвреден, но для чистоты лучше убрать)

---

## Проверка

После внесения правок соберите компонент `netsnmp`. Если компиляция проходит без ошибок
preprocessor/undefined symbols — слияние корректно. Все новые символы по умолчанию отключены,
что эквивалентно поведению 5.9.4 (эти возможности там не использовались).
