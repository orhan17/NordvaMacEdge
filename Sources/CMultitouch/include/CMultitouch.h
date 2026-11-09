#ifndef CMULTITOUCH_H
#define CMULTITOUCH_H

// MultitouchSupport.framework приватный: заголовка от Apple нет, раскладка
// восстановлена сообществом. Если Apple её поменяет, координаты станут мусором,
// поэтому размер структуры проверяется ещё при компиляции.

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
    MTVector2D normalized; // 0..1, начало координат в левом нижнем углу
    float size;
    int unknown1;
    float angle;
    float majorAxis;
    float minorAxis;
    MTVector2D absolute;
    int unknown2[2];
    float density;
} MTTouch;

_Static_assert(sizeof(MTTouch) == 96, "раскладка MTTouch не совпала с ожидаемой");

// Значения поля state: палец реально лежит на поверхности только в этих двух.
enum {
    MTTouchStateMakeTouch = 3,
    MTTouchStateTouching = 4,
};

#endif
