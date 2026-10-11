#ifndef TOUCH_MIDDLE_BRIDGE_H
#define TOUCH_MIDDLE_BRIDGE_H
#include <stdint.h>

#define TM_MAX_CONTACTS 32
typedef struct {
    int32_t identifier, state;
    float x, y, majorAxis, minorAxis, total;
} TMContact;
typedef struct {
    uint64_t device;
    double timestamp;
    int32_t sequence, count, invalidReason;
    TMContact contacts[TM_MAX_CONTACTS];
} TMFrame;
typedef void (*TMFrameSink)(void *context, const TMFrame *frame);

// Only one source per process. Frames are borrowed for the duration of the sink.
int TMStart(TMFrameSink sink, void *context, char *error, int errorCapacity);
void TMStop(void);
int TMDeviceCount(void);
int TMRunningDeviceCount(void);
const TMContact *TMFrameContact(const TMFrame *frame, int index);
int TMNativeContactSize(void);
void TMRequestAccessibilityPrompt(void);
#endif
