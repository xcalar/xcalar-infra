// Copyright 2018 Xcalar, Inc. All rights reserved.
//
// No use, or distribution, of this source code is permitted in any form or
// means without a valid, written license agreement with Xcalar, Inc.
// Please refer to the included "COPYING" file for terms and conditions
// regarding the use and redistribution of this software.

#include "GuardRails.h"

#include <sys/mman.h>

static int
circEmpty(MemFreeDelay *delay) {
    return (delay->head == delay->tail);
}

static int
circFull(MemFreeDelay *delay) {
    return ((delay->head + 1) % MAX_DELAY_ELMS == delay->tail);
}

static int
circCount(MemFreeDelay *delay) {
    if (circEmpty(delay)) {
        return 0;
    }

    size_t ct = delay->head > delay->tail ? delay->head - delay->tail :
                    MAX_DELAY_ELMS - (delay->tail - delay->head);
    GR_ASSERT_ALWAYS(ct == delay->numDelayed);
    return(delay->numDelayed);
}

static void
circPut(MemFreeDelay *delay, ElmHdr *hdr) {
    GR_ASSERT_ALWAYS(!circFull(delay));

    delay->elms[delay->head] = hdr;
    delay->head = (delay->head + 1) % MAX_DELAY_ELMS;
    delay->numDelayed++;
    delay->bytesDelayed += (1ULL << hdr->binNum);
}

static void *
circGet(MemFreeDelay *delay) {
    ElmHdr *hdr;

    GR_ASSERT_ALWAYS(!circEmpty(delay));
    hdr = delay->elms[delay->tail];
    delay->tail = (delay->tail + 1) % MAX_DELAY_ELMS;
    GR_ASSERT_ALWAYS(delay->numDelayed > 0);
    delay->numDelayed--;

    // We know that the allocation is at least PAGE_SIZE, and we need to read the
    // header to learn more.  So unprotect the header page here
    int ret = mprotect(hdr, PAGE_SIZE, PROT_READ | PROT_WRITE | PROT_EXEC);
    GR_ASSERT_ALWAYS(ret == 0);
    delay->bytesDelayed -= (1ULL << hdr->binNum);

    return(hdr);
}

static void
delayFreeBatch(MemSlot *slot) {
    while (circCount(&slot->delay) > MAX_DELAY_ELMS / 4) {
        ElmHdr *hdr = circGet(&slot->delay);
        const int binNum = hdr->binNum;
        const size_t elmSize = (1ULL << binNum);

        if (elmSize > PAGE_SIZE) {
            // circGet already unprotected the header page.  This page will
            // also accodomate allocations that happen to fit in the leftover
            // space.  For larger allocations, we must also unprotect any
            // additional pages.
            int ret = mprotect(hdr, elmSize, PROT_READ | PROT_WRITE | PROT_EXEC);
            GR_ASSERT_ALWAYS(ret == 0);
        }

        MemBin *bin = &slot->memBins[binNum];
        insertElmHead(&bin->headFree, hdr);
        bin->numFree++;
    }
}

void
delayPut(MemSlot *slot, ElmHdr *hdr) {
    GR_ASSERT_ALWAYS(verifyLocked(&slot->lock));
    if (circCount(&slot->delay) > MAX_DELAY_ELMS / 2) {
        delayFreeBatch(slot);
    }

    circPut(&slot->delay, hdr);

    const size_t elmSize = (1ULL << hdr->binNum);
    int ret = mprotect(hdr, elmSize, PROT_NONE);
    GR_ASSERT_ALWAYS(ret == 0);
}
