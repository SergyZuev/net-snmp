# Добавление новых заголовков в CMakeLists.var

В upstream 5.9.5 добавлены 3 новых системных заголовка. Поскольку списки исходников/заголовков
в вашей сборке явные (`set(headers ...)`), их нужно зарегистрировать вручную.

## Файл: `netsnmp/CMakeLists.var`

### Вставка 1 — после строки `include/net-snmp/system/freebsd14.h`

Добавьте две строки:
```cmake
include/net-snmp/system/freebsd15.h
include/net-snmp/system/freebsd16.h
```

Было:
```cmake
include/net-snmp/system/freebsd14.h
include/net-snmp/system/freebsd2.h
```

Стало:
```cmake
include/net-snmp/system/freebsd14.h
include/net-snmp/system/freebsd15.h
include/net-snmp/system/freebsd16.h
include/net-snmp/system/freebsd2.h
```

### Вставка 2 — после строки `include/net-snmp/system/openbsd7.h`

Добавьте одну строку:
```cmake
include/net-snmp/system/openbsd8.h
```

Было:
```cmake
include/net-snmp/system/openbsd7.h
include/net-snmp/system/osf5.h
```

Стало:
```cmake
include/net-snmp/system/openbsd7.h
include/net-snmp/system/openbsd8.h
include/net-snmp/system/osf5.h
```

## Примечание

Сами файлы заголовков уже включены в пакет обновления (лежат в `netsnmp/include/net-snmp/system/`).
Порядок строк в списке соответствует лексикографической сортировке, принятой в вашем файле
(freebsd14 перед freebsd2 и т.д.) — новые строки вставлены с сохранением этого порядка.

Другие компоненты (netsnmpagent, netsnmpmibs, snmpnetstat) не требуют правок списков:
все изменённые файлы уже зарегистрированы, новых/удалённых файлов в них нет.
