// Copyright 2017-2018 Xcalar, Inc. All rights reserved.
//
// No use, or distribution, of this source code is permitted in any form or
// means without a valid, written license agreement with Xcalar, Inc.
// Please refer to the included "COPYING" file for terms and conditions
// regarding the use and redistribution of this software.

#ifndef _GUARDRAILS_H_
#define _GUARDRAILS_H_

#include <stdlib.h>
#include <stddef.h>
#include <stdint.h>
#include <stdbool.h>
#include <pthread.h>

#define MIN(a, b) ((a) < (b) ? (a) : (b))
#define MAX(a, b) ((a) > (b) ? (a) : (b))
#define IS_POW2(val) ((val) != 0 && (((val) & ((val) - 1)) == 0))
#define MEMB_SZ(type, memb) sizeof(((type *) 0x0)->memb)

#define KB (1024ULL)
#define MB (1024ULL * 1024ULL)
#define GB (1024ULL * 1024ULL * 1024ULL)

#define likely(condition)   __builtin_expect(!!(condition), 1)
#define unlikely(condition) __builtin_expect(!!(condition), 0)

// Avoids any formatted output which can lead to malloc faults
#define GR_ASSERT_ALWAYS(cond) \
    do {\
        if (unlikely(!(cond))) {\
            abort();\
        }\
    }\
    while (0);

#define MAX_MEM_POOLS 256
#define MEMPOOL_MIN_EXPAND_SIZE (1000ULL * MB)
#define MAX_ALLOC_POWER 40
#define MAX_PREALLOC_POWER 18

// Multiplier for amount of pool to allocate over and above the amount requierd
// to meet all high water marks during init
#define START_POOL_MULT 2

// The maximum allocation that's allowed to be round-robined amongst all the
// slots.  Allocations exceeding this will all go to slot 0 to prevent
// scattering very large freed blocks across different slots.
#define MAX_FLOATING_SIZE (1 * MB)

// #define NUM_GP 0
#define NUM_GP 1
#define PAGE_SIZE 4096
#define MAX_SLOTS 128

#define ARG_MAX_BYTES 1024
#define ARG_MAX_NUM 64
#define ARG_FILE "grargs.txt"

#define TRACKER_FILE_PRE "grtrack"

#define MAGIC_INUSE 0x4ef9e433f005ba11ULL
#define MAGIC_FREE  0xcd656727bedabb1eULL
#define MAGIC_GUARD 0xfd44ba54deadbabeULL

#define MAGIC_SLOP 0xb6
#define MAX_SLOP 32

typedef struct GRArgs {
    size_t maxTrackFrames;
    size_t maxTrackFreeFrames;
    size_t numSlots;
    size_t maxMemPct;
    size_t slotHWMDumpIntervalBytes;
    // Maximum requested bytes allowed for a slot before GuardRails
    // will report and abort.  This doesn't include buf$ unless running
    // in malloc-backed buf$ mode.
    uint64_t maxRequestedBytes;
    uint8_t poisonVal;
    bool useDelay;
    bool verbose;
    bool poison;
    bool abortOnOOM;
    bool abortOnNull;
} GRArgs;

typedef struct ElmHdr {
    uint64_t magic;
    size_t binNum;
    size_t slotNum;
    // Pointer returned to user
    void *usrData;
    // Allocation size requested by user
    size_t usrDataSize;
    size_t misalignment;
    struct ElmHdr *next;
    struct ElmHdr *prev;
    void *allocBt[0];
} ElmHdr;

typedef struct MemPool {
    size_t totalSizeBytes;
    size_t remainingSizeBytes;
    // Start of this memory pool
    void *start;
    // Start of this pools free space
    void *startFree;
    // Last valid address; somewhat redundant
    void *end;
} MemPool;

#define MAX_DELAY_ELMS (32 * KB)
typedef struct MemFreeDelay {
    size_t head;
    size_t tail;
    // Number of elements in delay list
    size_t numDelayed;
    // Amount of memory in delay list
    size_t bytesDelayed;
    struct ElmHdr *elms[MAX_DELAY_ELMS];
} MemFreeDelay;

typedef struct MemBin {
    size_t allocs;
    size_t frees;
    size_t highWater;
    size_t lowWater;
    size_t numFree;
    struct ElmHdr *headFree;
    struct ElmHdr *headInUse;
} MemBin;

typedef struct MemSlot {
    MemBin memBins[MAX_ALLOC_POWER];
    MemFreeDelay delay;
    // Actual number of bytes requested by user, used to track allocator efficiency
    size_t totalUserRequestedBytes;
    size_t totalUserFreedBytes;
    size_t HWMUsrBytes;
    size_t lastHWMUsrBytesDump;
    pthread_mutex_t lock; // Move to MemBin
} MemSlot;

typedef struct MemHisto {
    size_t allocs;
    size_t frees;
} MemHisto;

void delayPut(MemSlot *slot, ElmHdr *hdr);
void insertElmHead(struct ElmHdr **head, struct ElmHdr *elm);
bool verifyLocked(pthread_mutex_t *lock);

#endif // _GUARDRAILS_H_
