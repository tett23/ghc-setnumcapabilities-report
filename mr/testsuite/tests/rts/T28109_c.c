#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>

/* A watchdog on an OS thread of its own, created directly with the
   platform thread API rather than by the RTS, so that it keeps running
   when the RTS has deadlocked.  After `seconds` it ends the process with
   exit code 1, which fails the test instead of waiting for the testsuite
   timeout. */

#if defined(_WIN32)
#include <windows.h>

static DWORD WINAPI watchdog_main(LPVOID arg)
{
    int seconds = (int)(intptr_t)arg;
    Sleep((DWORD)seconds * 1000);
    fprintf(stderr, "T28109: still running after %d s, giving up\n", seconds);
    fflush(stderr);
    _exit(1);
    return 0;
}

void start_watchdog(int seconds)
{
    HANDLE h = CreateThread(NULL, 0, watchdog_main, (LPVOID)(intptr_t)seconds, 0, NULL);
    if (h != NULL) CloseHandle(h);
}

#else
#include <pthread.h>
#include <unistd.h>

static void *watchdog_main(void *arg)
{
    int seconds = (int)(intptr_t)arg;
    sleep((unsigned)seconds);
    fprintf(stderr, "T28109: still running after %d s, giving up\n", seconds);
    fflush(stderr);
    _exit(1);
    return NULL;
}

void start_watchdog(int seconds)
{
    pthread_t t;
    if (pthread_create(&t, NULL, watchdog_main, (void *)(intptr_t)seconds) == 0) {
        pthread_detach(t);
    }
}
#endif
