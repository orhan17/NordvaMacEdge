#ifndef CMULTITOUCH_H
#define CMULTITOUCH_H

// MultitouchSupport.framework is private and ships no header. This layout is
// community-reverse-engineered; if Apple changes it, coordinates turn into garbage,
// hence the size check below.

typedef struct {
    float x;
    float y;
} MTPoint2D;

typedef struct {
    MTPoint2D position;
    MTPoint2D velocity;
} MTVector2D;

typedef struct {
    int frame;
    double timestamp;
    int identifier;
    int state;
    int fingerID;
    int handID;
    MTVector2D normalized;
    float size;
    int unknown1;
    float angle;
    float majorAxis;
    float minorAxis;
    MTVector2D absolute;
    int unknown2[2];
    float density;
} MTTouch;

_Static_assert(sizeof(MTTouch) == 96, "unexpected MTTouch layout");

enum {
    MTTouchStateMakeTouch = 3,
    MTTouchStateTouching = 4,
};

#endif
