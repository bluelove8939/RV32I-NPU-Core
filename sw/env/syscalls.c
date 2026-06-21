#include <stddef.h>
#include <stdint.h>
#include <sys/stat.h>

#include "nmta_syscall.h"

extern char __heap_start[];
extern char __heap_end[];

static char *heap_cur;

static int is_stdio_fd(int fd)
{
    return fd >= 0 && fd <= 2;
}

void *_sbrk(ptrdiff_t incr)
{
    if (heap_cur == NULL) {
        heap_cur = __heap_start;
    }

    char *old = heap_cur;
    char *next = heap_cur + incr;

    if (next < __heap_start || next > __heap_end) {
        return (void *)-1;
    }

    heap_cur = next;
    return old;
}

int _write(int fd, const void *buf, size_t count)
{
    if ((fd != 1 && fd != 2) || buf == NULL) {
        return -1;
    }

    asm volatile ("fence" ::: "memory");
    return (int)nmta_ecall3(NMTA_SYS_WRITE,
                            (long)fd,
                            (long)buf,
                            (long)count);
}

int _read(int fd, void *buf, size_t count)
{
    return (int)nmta_ecall3(NMTA_SYS_READ,
                            (long)fd,
                            (long)buf,
                            (long)count);
}

int _close(int fd)
{
    return is_stdio_fd(fd) ? 0 : -1;
}

int _lseek(int fd, int offset, int whence)
{
    (void)offset;
    (void)whence;

    return is_stdio_fd(fd) ? 0 : -1;
}

int _fstat(int fd, struct stat *st)
{
    if (!is_stdio_fd(fd) || st == NULL) {
        return -1;
    }

    st->st_mode = S_IFCHR;
    return 0;
}

int _isatty(int fd)
{
    return is_stdio_fd(fd);
}

int _getpid(void)
{
    return 1;
}

int _kill(int pid, int sig)
{
    (void)pid;
    (void)sig;
    return -1;
}
