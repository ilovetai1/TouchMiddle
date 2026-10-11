#include "CTouchBridge.h"
#include <CoreFoundation/CoreFoundation.h>
#include <ApplicationServices/ApplicationServices.h>
#include <dlfcn.h>
#include <math.h>
#include <pthread.h>
#include <stdbool.h>
#include <stdio.h>
#include <string.h>
#include <stddef.h>
#include <stdatomic.h>

// Private ABI independently described by recent MoreTouch/OpenMultitouchSupport
// headers. A runtime probe must validate fields on each OS/device combination.
typedef void *MTDevice;
typedef struct { float x, y; } MTPoint;
typedef struct { MTPoint position, velocity; } MTVector;
typedef struct {
    int32_t frame;
    double timestamp;
    int32_t identifier, state, fingerID, handID;
    MTVector normalized;
    float total, pressure, angle, majorAxis, minorAxis;
    MTVector absolute;
    int32_t unknown14, unknown15;
    float density;
} MTContact;
_Static_assert(sizeof(MTContact) == 96, "Unexpected private contact ABI");
_Static_assert(offsetof(MTContact, normalized) == 32, "Unexpected position ABI");

typedef void (*MTCallback)(MTDevice, MTContact *, int, double, int);
static CFArrayRef (*createList)(void);
static void (*registerCallback)(MTDevice, MTCallback);
static void (*unregisterCallback)(MTDevice, MTCallback);
static void (*startDevice)(MTDevice, int);
static void (*stopDevice)(MTDevice);
static bool (*isRunning)(MTDevice);
static bool (*isBuiltIn)(MTDevice);
static void *framework;
static CFArrayRef devices;
static MTDevice selected[32];
static int selectedCount;
static pthread_mutex_t sinkLock = PTHREAD_MUTEX_INITIALIZER;
static TMFrameSink frameSink;
static void *sinkContext;
static _Atomic uint64_t captureEpoch;

static void receiveFrame(MTDevice device, MTContact *data, int count, double timestamp, int sequence) {
    // A callback that began copying before a stop/restart must not be delivered
    // to the replacement sink. Lifecycle calls run serially on the main actor.
    uint64_t entryEpoch = atomic_load_explicit(&captureEpoch, memory_order_acquire);
    TMFrame frame = { .device = (uint64_t)(uintptr_t)device, .timestamp = timestamp,
        .sequence = sequence, .count = count, .invalidReason = 0 };
    if (count < 0 || count > TM_MAX_CONTACTS || (count > 0 && !data)) {
        frame.invalidReason = 1;
        frame.count = 0;
    } else if (!isfinite(timestamp) || timestamp < 0) {
        frame.invalidReason = 2;
        frame.count = 0;
    } else {
        for (int i = 0; i < count; i++) {
            MTContact *c = &data[i];
            float x = c->normalized.position.x, y = c->normalized.position.y;
            if (c->state < 0 || c->state > 7 || !isfinite(x) || !isfinite(y) ||
                !isfinite(c->timestamp) || !isfinite(c->majorAxis) || !isfinite(c->minorAxis) || !isfinite(c->total) ||
                x < -0.2f || x > 1.2f || y < -0.2f || y > 1.2f) {
                frame.invalidReason = 3;
                frame.count = 0;
                break;
            }
            frame.contacts[i] = (TMContact){ .identifier = c->identifier, .state = c->state,
                .x = x, .y = y, .majorAxis = c->majorAxis, .minorAxis = c->minorAxis, .total = c->total };
        }
    }
    // Stop clears the sink under this lock before releasing its context.
    pthread_mutex_lock(&sinkLock);
    if (frameSink && entryEpoch == atomic_load_explicit(&captureEpoch, memory_order_acquire))
        frameSink(sinkContext, &frame);
    pthread_mutex_unlock(&sinkLock);
}

static int fail(char *error, int capacity, const char *message) {
    if (error && capacity > 0) snprintf(error, (size_t)capacity, "%s", message);
    return -1;
}

int TMStart(TMFrameSink sink, void *context, char *error, int capacity) {
    if (selectedCount || frameSink) return fail(error, capacity, "Touch source is already active");
    if (!sink) return fail(error, capacity, "A frame sink is required");
    if (!framework) {
        framework = dlopen("/System/Library/PrivateFrameworks/MultitouchSupport.framework/MultitouchSupport", RTLD_NOW | RTLD_LOCAL);
        if (!framework) return fail(error, capacity, dlerror());
        createList = dlsym(framework, "MTDeviceCreateList");
        registerCallback = dlsym(framework, "MTRegisterContactFrameCallback");
        unregisterCallback = dlsym(framework, "MTUnregisterContactFrameCallback");
        startDevice = dlsym(framework, "MTDeviceStart");
        stopDevice = dlsym(framework, "MTDeviceStop");
        isRunning = dlsym(framework, "MTDeviceIsRunning");
        isBuiltIn = dlsym(framework, "MTDeviceIsBuiltIn");
    }
    if (!createList || !registerCallback || !unregisterCallback || !startDevice || !stopDevice || !isRunning || !isBuiltIn)
        return fail(error, capacity, "Required MultitouchSupport symbols are unavailable");
    devices = createList();
    if (!devices) return fail(error, capacity, "MTDeviceCreateList returned no list");
    CFIndex n = CFArrayGetCount(devices);
    for (CFIndex i = 0; i < n && selectedCount < 32; i++) {
        MTDevice device = (MTDevice)CFArrayGetValueAtIndex(devices, i);
        if (isBuiltIn(device)) selected[selectedCount++] = device;
    }
    // MVP deliberately targets the internal trackpad observed on this Mac.
    if (!selectedCount) { CFRelease(devices); devices = NULL; return fail(error, capacity, "No built-in multitouch device found"); }
    pthread_mutex_lock(&sinkLock);
    atomic_fetch_add_explicit(&captureEpoch, 1, memory_order_release);
    frameSink = sink; sinkContext = context;
    pthread_mutex_unlock(&sinkLock);
    for (int i = 0; i < selectedCount; i++) { registerCallback(selected[i], receiveFrame); startDevice(selected[i], 0); }
    int running = TMRunningDeviceCount();
    if (!running) { TMStop(); return fail(error, capacity, "No device reports running after MTDeviceStart"); }
    if (error && capacity > 0) error[0] = '\0';
    return selectedCount;
}

void TMStop(void) {
    pthread_mutex_lock(&sinkLock);
    atomic_fetch_add_explicit(&captureEpoch, 1, memory_order_release);
    frameSink = NULL; sinkContext = NULL;
    pthread_mutex_unlock(&sinkLock);
    for (int i = 0; i < selectedCount; i++) { unregisterCallback(selected[i], receiveFrame); stopDevice(selected[i]); }
    selectedCount = 0;
    if (devices) { CFRelease(devices); devices = NULL; }
}
int TMDeviceCount(void) { return selectedCount; }
int TMRunningDeviceCount(void) {
    int n = 0;
    for (int i = 0; i < selectedCount; i++) if (isRunning(selected[i])) n++;
    return n;
}
const TMContact *TMFrameContact(const TMFrame *frame, int index) {
    if (!frame || index < 0 || index >= frame->count || index >= TM_MAX_CONTACTS) return NULL;
    return &frame->contacts[index];
}
int TMNativeContactSize(void) { return (int)sizeof(MTContact); }
void TMRequestAccessibilityPrompt(void) {
    const void *keys[] = { kAXTrustedCheckOptionPrompt };
    const void *values[] = { kCFBooleanTrue };
    CFDictionaryRef options = CFDictionaryCreate(kCFAllocatorDefault, keys, values, 1,
        &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
    AXIsProcessTrustedWithOptions(options);
    CFRelease(options);
}
