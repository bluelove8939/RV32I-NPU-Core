#include <stddef.h>

extern int _write(int fd, const void *buf, size_t count);
extern void *_sbrk(ptrdiff_t incr);

int main(void)
{
    static const char message[] = "NMTA ABI smoke\n";
    char *heap = (char *)_sbrk(16);

    if (heap == (void *)-1) {
        return 2;
    }

    heap[0] = 'O';
    heap[1] = 'K';
    heap[2] = '\n';

    if (_write(1, message, sizeof(message) - 1) !=
        (int)(sizeof(message) - 1)) {
        return 3;
    }

    if (_write(1, heap, 3) != 3) {
        return 4;
    }

    return 0;
}
