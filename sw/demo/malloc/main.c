#include <stdio.h>
#include <stdlib.h>

int main() {
    char *ptr = malloc(100); // Allocate 100 bytes of memory
    if (ptr == NULL) {
        fprintf(stderr, "Memory allocation failed\n");
        return 1; // Exit with an error code
    }
    fprintf(stdout, "Memory allocated successfully at address: %p\n", (void *)ptr);
    free(ptr); // Free the allocated memory
    return 0;
}