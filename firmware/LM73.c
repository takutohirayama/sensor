#include "lm73.h"
#include "main.h"

#include <string.h>

#include "f38x_i2c.h"
#include "data_hub.h"
#include "util.h"
#include "c8051f380.h"

#define I2C_ADDRESS_LM (0x4c << 1)

static __xdata u8 lm73_data[SYLPHIDE_PAGESIZE - 16];

/*
 * X page design =>
 * 'X', 0, 0, tickcount & 0xFF, // + 4
 * global_ms(4 bytes), // + 8
 * [0] AD0,1,3(big endian, 3 bytes * 3), temperature(big endain, 3 bytes) // + 20
 * [1] AD0,1,3(big endian, 3 bytes * 3), temperature(big endain, 3 bytes) // + 32
 */

volatile __bit lm73_capture;
static u8 capture_cycle;

//#define i2c_read_write i2c0_read_write
#define i2c_read_write i2c1_read_write

static void send_cmd(u8 cmd){
  i2c_read_write(I2C_WRITE(I2C_ADDRESS_LM), &cmd, sizeof(cmd));
}

static void write_register(u8 addr, u8 value){
  u8 buf[] = {(0x4c | addr << 2), value};
  i2c_read_write(I2C_WRITE(I2C_ADDRESS_LM), buf, sizeof(buf));
}

void lm73_init(){
  write_register(4, 0x60); // 14bits mode
  send_cmd(0x00); // START/SYNC
  //capture_cycle = 0;
  lm73_capture = FALSE;
}

static void make_packet(packet_t *packet){
  payload_t *dst = packet->current;
  
  // Check whether buffer size is sufficient
  if((packet->buf_end - dst) < SYLPHIDE_PAGESIZE){
    return;
  }
    
  *(dst++) = 'X';
  *(dst++) = 0;
  *(dst++) = 0;
  *(dst++) = u32_lsbyte(tickcount);
  
  // Record time, LSB first
  memcpy(dst, &global_ms, sizeof(global_ms));
  dst += sizeof(global_ms);
  
  memcpy(dst, lm73_data, sizeof(lm73_data));
  dst += sizeof(lm73_data);
  
  packet->current = dst;
}

void lm73_polling(){
  static __xdata u8 * __xdata next_buf = lm73_data;
  if(lm73_capture){
    lm73_capture = FALSE;
    
    send_cmd(0x10);
    
    for(int i = 0; i < 2; i++){
      u8 data;
      if(i2c_read_write(I2C_READ(I2C_ADDRESS_LM), &data, sizeof(data)) == sizeof(data)){
        *(next_buf++) = data;
      }
    }
    
    if (data<0){
      data=-data;
    }
  }
}

/*void ads122_polling(){
  
  static __xdata u8 * __xdata next_buf = ads122_data;
  
  if(ads122_capture){
    ads122_capture = FALSE;
    
    send_cmd(0x10);
    i2c_read_write(I2C_READ(I2C_ADDRESS_RW), next_buf, 3);
    next_buf += 3;
/*
    
   /*switch(capture_cycle++){
      case 0:
      case 4:
        write_register(0, 0x90); // Register 0, AINP = AIN1, AINN = AVSS
        break;
      case 1:
      case 5:
        write_register(0, 0xB0); // Register 0, AINP = AIN3, AINN = AVSS
        break;
      case 2:
      case 6:
        write_register(1, 0x69); // Register 1, 175SPS, Continuous conversion, temperature ON
        break;
      case 7: // Rotate
        capture_cycle = 0;
        data_hub_assign_page(make_packet);
        next_buf = ads122_data;
      case 3:
        write_register(1, 0x68); // Register 1, 175SPS, Continuous conversion, temperature OFF
        write_register(0, 0x80); // Register 0, AINP = AIN0, AINN = AVSS
        break;
    */
    }
  }
}
