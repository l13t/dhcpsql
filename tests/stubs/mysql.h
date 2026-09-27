#ifndef TEST_MYSQL_H
#define TEST_MYSQL_H
/* Minimal MySQL double: exercise DHCP code without a database service. */
typedef struct { int unused; } MYSQL;
typedef struct { int unused; } MYSQL_RES;
typedef char **MYSQL_ROW;
enum mysql_option { MYSQL_OPT_CONNECT_TIMEOUT, MYSQL_OPT_READ_TIMEOUT, MYSQL_OPT_WRITE_TIMEOUT };
MYSQL *mysql_init(MYSQL *);
int mysql_options(MYSQL *, enum mysql_option, const void *);
MYSQL *mysql_real_connect(MYSQL *, const char *, const char *, const char *, const char *, unsigned int, const char *, unsigned long);
void mysql_close(MYSQL *);
const char *mysql_error(MYSQL *);
unsigned int mysql_errno(MYSQL *);
int mysql_query(MYSQL *, const char *);
MYSQL_RES *mysql_store_result(MYSQL *);
MYSQL_ROW mysql_fetch_row(MYSQL_RES *);
void mysql_free_result(MYSQL_RES *);
unsigned long long mysql_num_rows(MYSQL_RES *);
#endif
