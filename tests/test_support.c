/* Unit tests do not need daemon logging, sockets or pid files. */
void udhcp_logging(int level, const char *fmt, ...)
{
    (void)level;
    (void)fmt;
}
