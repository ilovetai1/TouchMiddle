#include "CTouchBridge.h"
#include <CoreFoundation/CoreFoundation.h>
#include <ApplicationServices/ApplicationServices.h>
#include <stdio.h>
#include <signal.h>
#include <unistd.h>
#include <stdlib.h>
#include <pthread.h>
#include <sys/stat.h>
#include <time.h>

static volatile sig_atomic_t interrupted;
static FILE *trace;
static pthread_mutex_t statsLock = PTHREAD_MUTEX_INITIALIZER;
static unsigned long frames, nonempty, invalid, activeHistogram[33];
static double lastTimestamp, maximumGap;
static int backwards;
static void signalHandler(int value) { interrupted = 1; }
static void receive(void *context, const TMFrame *f) {
    pthread_mutex_lock(&statsLock);
    frames++; invalid += f->invalidReason != 0;
    int active = 0;
    for (int i = 0; i < f->count; i++) if (f->contacts[i].state == 3 || f->contacts[i].state == 4) active++;
    if (active) nonempty++;
    activeHistogram[active]++;
    if (lastTimestamp && f->timestamp < lastTimestamp) backwards++;
    if (lastTimestamp && f->timestamp - lastTimestamp > maximumGap) maximumGap = f->timestamp - lastTimestamp;
    lastTimestamp = f->timestamp;
    if (trace) {
        fprintf(trace, "{\"device\":%llu,\"timestamp\":%.9f,\"sequence\":%d,\"invalidReason\":%d,\"contacts\":[", (unsigned long long)f->device,f->timestamp,f->sequence,f->invalidReason);
        for (int i = 0; i < f->count; i++) {
            const TMContact *c = &f->contacts[i];
            fprintf(trace, "%s{\"id\":%d,\"state\":%d,\"x\":%.6f,\"y\":%.6f,\"major\":%.4f,\"minor\":%.4f}",i?",":"",c->identifier,c->state,c->x,c->y,c->majorAxis,c->minorAxis);
        }
        fprintf(trace,"]}\n");
    }
    pthread_mutex_unlock(&statsLock);
}
int main(int argc, char **argv) {
    int seconds = argc > 1 ? atoi(argv[1]) : 120;
    if (seconds < 1 || seconds > 1800) return 2;
    if (argc > 2) { trace = fopen(argv[2], "w"); if (!trace) { perror("trace"); return 2; } chmod(argv[2],0600); }
    signal(SIGINT,signalHandler); signal(SIGTERM,signalHandler);
    char error[512]; int started = TMStart(receive,NULL,error,sizeof(error));
    if (started < 0) { fprintf(stderr,"touch_source_failed: %s\n",error); if(trace)fclose(trace); return 1; }
    printf("{\"event\":\"started\",\"devices\":%d,\"running\":%d,\"nativeContactBytes\":%d,\"accessibility\":%s,\"postEventAccess\":%s,\"listenEventAccess\":%s,\"seconds\":%d}\n",started,TMRunningDeviceCount(),TMNativeContactSize(),AXIsProcessTrusted()?"true":"false",CGPreflightPostEventAccess()?"true":"false",CGPreflightListenEventAccess()?"true":"false",seconds); fflush(stdout);
    time_t end = time(NULL) + seconds;
    while (!interrupted && time(NULL) < end) {
        CFRunLoopRunInMode(kCFRunLoopDefaultMode,1.0,false);
        pthread_mutex_lock(&statsLock);
        printf("{\"event\":\"heartbeat\",\"frames\":%lu,\"nonempty\":%lu,\"invalid\":%lu,\"one\":%lu,\"two\":%lu,\"three\":%lu,\"fourPlus\":%lu}\n",frames,nonempty,invalid,activeHistogram[1],activeHistogram[2],activeHistogram[3],nonempty-activeHistogram[1]-activeHistogram[2]-activeHistogram[3]); fflush(stdout);
        if(trace)fflush(trace);
        pthread_mutex_unlock(&statsLock);
    }
    TMStop();
    printf("{\"event\":\"stopped\",\"frames\":%lu,\"nonempty\":%lu,\"invalid\":%lu,\"backwards\":%d,\"maximumGapSeconds\":%.4f,\"running\":%d}\n",frames,nonempty,invalid,backwards,maximumGap,TMRunningDeviceCount());
    if(trace)fclose(trace);
    return frames && nonempty && !invalid && !backwards ? 0 : 3;
}
