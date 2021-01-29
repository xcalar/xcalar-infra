LIBDIRS=-Llibunwind-1.3-rc1/src/.libs/
INCDIRS=-Ilibunwind-1.3-rc1/include/
CFLAGS=-std=gnu99 -O2 -fno-omit-frame-pointer -fno-builtin-malloc -ggdb -Wall -fPIC -D_GNU_SOURCE $(LIBDIRS) $(INCDIRS) -Werror=implicit-function-declaration

LUNWIND:=http://netstore/users/ecohen/public/guardrails/deps/libunwind-1.3-rc1.tar.gz

CC=gcc
AR=ar

all: libguardrails.a libguardrails.so.0.0 test

libguardrails.a: GuardRails.o DelayFree.o
	rm -f $@
	$(AR) crv $@ $?

libguardrails.so.0.0: GuardRails.o DelayFree.o
	$(CC) -shared -Wl,-soname,libguardrails.so.0 -o $@ \
	    $(CFLAGS) $? -lpthread -lc -l:libunwind.a -l:libunwind-x86_64.a

GuardRails.o: GuardRails.c GuardRails.h
	$(CC) $(CFLAGS) -c $< -o $@

DelayFree.o: DelayFree.c GuardRails.h
	$(CC) $(CFLAGS) -c $< -o $@

test: test.o
	$(CC) -o $@ test.o

test.o: test.c
	$(CC) $(CFLAGS) -c $< -o $@

clean:
	rm -f test *.o libguardrails.a libguardrails.so.0.0

deps:
	# See http://download.savannah.nongnu.org/releases/libunwind/
	curl $(LUNWIND) | tar -zxf -
	cd libunwind-1.3-rc1 && ./configure --with-pic && patch -p2 < ../libunwindcfg.patch && make

clean-deps:
	rm -rf libunwind-1.3-rc1
