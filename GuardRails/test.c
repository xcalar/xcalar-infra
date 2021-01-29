// Copyright 2017 Xcalar, Inc. All rights reserved.
//
// No use, or distribution, of this source code is permitted in any form or
// means without a valid, written license agreement with Xcalar, Inc.
// Please refer to the included "COPYING" file for terms and conditions
// regarding the use and redistribution of this software.

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/types.h>
#include <unistd.h>
#include <time.h>
#include <stdint.h>

#define IMAX 100
#define JMAX 4000

extern char __executable_start;
extern char __etext;

void allocLeak(void) {
#if 1
    char *buf = malloc(20);
    buf[0] = 1;
#endif
}

void useAfterFree(void) {
    int *ptr = malloc(sizeof(int));

    *ptr = 7;
    // fool optimizer
    printf("ptr: %d\n", *ptr);
    free(ptr);
    printf("ptr: %d\n", *ptr);
    *ptr = 8;
    printf("ptr: %d\n", *ptr);
}

int
main() {
    srand(time(NULL));
    int i, j;
    const int maxRand = (1 << 16);

    printf("exec start: %p\n", &__executable_start);
    printf("imax:jmax:sz: %d:%d:%d\n", IMAX, JMAX, maxRand);
    do {
        for (i = 0; i < IMAX; i++) {
            size_t totalMem = 0;
            void *bufs[JMAX];
            memset(bufs, 0, sizeof(void *)*JMAX);
            allocLeak();
            for (j = 0; j < JMAX; j++) {
                int randSize = rand() % maxRand;
                // int randSize = (rand() % maxRand) / 8 * 8;
                // printf("%d:%d: %6d\n", i, j, randSize);
                bufs[j] = malloc(randSize);
                memset(bufs[j], 0x5a, randSize);
                char *ptr  = (char *)bufs[j] + randSize;
                (void)ptr;
                // if (randSize % 16 == 0) {
                    *(ptr++) = 1;
                // }
#if 0
                *(ptr++) = 1;
                *(ptr++) = 1;
                *(ptr++) = 1;
                *(ptr++) = 1;
                *(ptr++) = 1;
                *(ptr++) = 1;
                *(ptr++) = 1;
#endif
                free(bufs[j]);
                totalMem += randSize;
            }
#if 0
            // sleep(5);
            for (j = 0; j < JMAX; j++) {
                free(bufs[j]);
                bufs[j] = NULL;
            }
#endif
        }
        printf("enter to continue\n");
        //getchar();
    } while (0);

    // useAfterFree();
    return (0);
}
