#include "n5_regs.h"
#include "n5_drv.h"

/* interrupts */
void enable_global_interrupt() {
    asm volatile("csrs  mstatus, %0\n" : : "r"(0x8));
}
//UART 0
void enable_irq0() {
    asm volatile("csrs  mie, %0\n" : : "r"(0x10000));
}
//UART 1
void enable_irq1(){
   asm volatile("csrs  mie, %0\n" : : "r"(0x20000));
}
//SPI 0
void enable_irq2(){
   asm volatile("csrs  mie, %0\n" : : "r"(0x40000));
}
//SPI 1
void enable_irq3(){
   asm volatile("csrs  mie, %0\n" : : "r"(0x80000));
}
//I2C 0
void enable_irq4(){
   asm volatile("csrs  mie, %0\n" : : "r"(0x100000));
}
//I2C 1
void enable_irq5(){
   asm volatile("csrs  mie, %0\n" : : "r"(0x200000));
}
//TMR 0
void enable_irq6(){
   asm volatile("csrs  mie, %0\n" : : "r"(0x400000));
}
//TMR 1
void enable_irq7(){
   asm volatile("csrs  mie, %0\n" : : "r"(0x800000));
}
//TMR 2
void enable_irq8(){
   asm volatile("csrs  mie, %0\n" : : "r"(0x1000000));
}
//TMR 3
void enable_irq9(){
   asm volatile("csrs  mie, %0\n" : : "r"(0x2000000));
}
//WDT 0
void enable_irq10(){
   asm volatile("csrs  mie, %0\n" : : "r"(0x4000000));
}
//WDT 1
void enable_irq11(){
   asm volatile("csrs  mie, %0\n" : : "r"(0x8000000));
}




/* GPIO */
void gpio_set_dir(unsigned int d) { 
    *GPIO_DIR = d; 
}

void gpio_write(unsigned int d) { 
    *GPIO_DOUT = d;
}


unsigned int gpio_read() {  
    return *GPIO_DIN;
}

void gpio_pull (unsigned char d){
    *GPIO_PD = 0;
    *GPIO_PU = 0;
    if(d==0) *GPIO_PD = 1;
    else *GPIO_PU = 1;
}

void gpio_im(unsigned int im){
    *GPIO_IM = im;
}

/* UART */
int uart_init(unsigned int n, unsigned int prescaler){
   // if(n>1) return -1;
    if(n==1){
        *UART1_PRESCALER = prescaler;
        *UART1_IM = 0;
        *UART1_CTRL = 1;
    }
    else if (n==0){
        *UART0_PRESCALER = prescaler;
        *UART0_IM = 0;
        *UART0_CTRL = 1;
    }
}

int uart_puts(unsigned int n, unsigned char *msg, unsigned int len){
    int i;
    if(n>1) return -1;
    if(n==0){
        for(i=0; i<len; i++){
            while(*UART0_STATUS&1); // TX Not Full
            *UART0_DATA = msg[i]; 
        }
    }  else if (n==1){
        for(i=0; i<len; i++){
            while(*UART1_STATUS&1); // TX Not Full
            *UART1_DATA = msg[i]; 
        }
    }   
    return 0;
}

int uart_gets(unsigned int n, unsigned char *msg, unsigned int len){
    int i;
    if(n>1) return -1;
    if(n==0){
    //*UART0_DATA= 'N';
    // msg[0] = *UART0_DATA;
        for(i=0; i<len; i++){
           while(*UART0_STATUS&8); // RX Not Empty
            msg[i] = *UART0_DATA;  
          //  msg[i]= 'N';
        }
    } else {
        for(i=0; i<len; i++){
            while(*UART1_STATUS&8); // RX Not Empty
            msg[i] = *UART1_DATA;  
        }
    }    
    return 0;
}

int uart_im (unsigned int n, unsigned int im){
    if(n>1) return -1;
    if(n==0){
    	*UART0_IM = im;
    }
    else {
    	*UART1_IM = im;
    }

}

/* SPI */
int spi_init(unsigned int n, unsigned char cpol, unsigned char cpha, unsigned char clkdiv){
  unsigned int cfg_value = 0;
  cfg_value |=  cpol;
  cfg_value |=  (cpha << 1);
  cfg_value |=  ((unsigned int)clkdiv << 2);
  if(n>1) return -1;
  if(n==0)  *SPI0_CFG = cfg_value;
  else *SPI1_CFG = cfg_value;
}

unsigned int spi_status(unsigned int n){
    if(n>1) return -1;
    if(n==0)    
        return *SPI0_STATUS & 1;
    else 
        return *SPI1_STATUS & 1;
}

unsigned char spi_read(unsigned int n){
    if(n>1) return -1;
    if(n==0)  
        return *SPI0_DATA;
    else 
        return *SPI1_DATA;
}

int spi_write(unsigned int n, unsigned char data){
    if(n>1) return -1;
    if(n==0) {
        *SPI0_DATA =  data;
        SET_BIT(*SPI0_CTRL, SPI_GO_BIT);
        CLR_BIT(*SPI0_CTRL, SPI_GO_BIT);
        while(!spi_status(n));
    } else{
        *SPI1_DATA =  data;
        SET_BIT(*SPI1_CTRL, SPI_GO_BIT);
        CLR_BIT(*SPI1_CTRL, SPI_GO_BIT);
        while(!spi_status(n));
    }
    return 0;
}

int spi_start(unsigned int n){
    if(n>1) return -1;
    if(n==0) {    
        SET_BIT(*SPI0_CTRL, SPI_SS_BIT);
    } else {
        SET_BIT(*SPI1_CTRL, SPI_SS_BIT);
    }
    return 0;
}

int spi_end(unsigned int n){
    if(n>1) return -1;
    if(n==0)    
        CLR_BIT(*SPI0_CTRL, SPI_SS_BIT);
    else 
        CLR_BIT(*SPI1_CTRL, SPI_SS_BIT);
    return 0;
}

int spi_im (unsigned int n, unsigned int im){
    if(n>1) return -1;
    if(n==0){
    	*SPI0_IM = im;
    }
    else {
    	*SPI1_IM = im;
    }

}
