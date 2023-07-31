#ifndef __LM73_H__
#define __LM73_H__

#include "type.h"

extern volatile __bit ads122_capture;

void lm73_init();
void lm73_polling();

#endif /* __LM73_H__ */
