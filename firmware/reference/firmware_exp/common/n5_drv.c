#include "n5_regs.h"
#include "n5_drv.h"

/* interrupts */
void enable_global_interrupt(){

   asm volatile("csrs  mstatus, %0\n" : : "r"(0x8));

}
//UART 0
void enable_irq0(){
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

/* i2c */
int i2c_init(unsigned int n, unsigned int pre){
    if(n>1) return -1;
    if(n==0) {
        *(I2C0_PRE_LO) = pre & 0xff;
        *(I2C0_PRE_HI) = pre & 0xff00;
        *(I2C0_CTRL) = I2C_CTRL_EN | I2C_CTRL_IEN;
    } else {
        *(I2C1_PRE_LO) = pre & 0xff;
        *(I2C1_PRE_HI) = pre & 0xff00;
        *(I2C1_CTRL) = I2C_CTRL_EN | I2C_CTRL_IEN;
    }
}

int i2c_send(unsigned int n, unsigned char saddr, unsigned char sdata){   //send only one char!!!
    if(n>1) return -1;
    if(n==0) {
        *(I2C0_TX) = saddr;
        *(I2C0_CMD) = I2C_CMD_STA | I2C_CMD_WR;
        while( ((*I2C0_STAT) & I2C_STAT_TIP) != 0 );
        //(*I2C_STAT) & I2C_STAT_TIP ;

        if( ((*I2C0_STAT) & I2C_STAT_RXACK)) {
            *(I2C0_CMD) = I2C_CMD_STO;
            return 0;
        }
        *(I2C0_TX) = sdata;
        *(I2C0_CMD) = I2C_CMD_WR;
        while( (*I2C0_STAT) & I2C_STAT_TIP );
        *(I2C0_CMD) = I2C_CMD_STO;
        if( ((*I2C0_STAT) & I2C_STAT_RXACK ))
            return 0;
        else
            return 1;
    } else {
        *(I2C1_TX) = saddr;
        *(I2C1_CMD) = I2C_CMD_STA | I2C_CMD_WR;
        while( ((*I2C1_STAT) & I2C_STAT_TIP) != 0 );
        //(*I2C_STAT) & I2C_STAT_TIP ;

        if( ((*I2C1_STAT) & I2C_STAT_RXACK)) {
            *(I2C1_CMD) = I2C_CMD_STO;
            return 0;
        }
        *(I2C1_TX) = sdata;
        *(I2C1_CMD) = I2C_CMD_WR;
        while( (*I2C1_STAT) & I2C_STAT_TIP );
        *(I2C1_CMD) = I2C_CMD_STO;
        if( ((*I2C1_STAT) & I2C_STAT_RXACK ))
            return 0;
        else
            return 1;
    }
}

/* PWM */
int pwm_init(unsigned int n, unsigned int cmp1, unsigned int cmp2, unsigned int pre){
  if(n>1) return -1;
    if(n==0) {
        *PWM0_CMP1 = cmp1;
        *PWM0_CMP2 = cmp2;
        *PWM0_PRE = pre;
    } else {
        *PWM1_CMP1 = cmp1;
        *PWM1_CMP2 = cmp2;
        *PWM1_PRE = pre;
    }
    return 0;
}

int pwm_enable(unsigned int n){
    if(n>1) return -1;
    if(n==0) 
        *PWM0_CTRL = 0x1;
    else
        *PWM1_CTRL = 0x1;
    return 0;
}

int pwm_disable(unsigned int n){
    if(n>1) return -1;
    if(n==0) 
        *PWM0_CTRL = 0x0;
    else
        *PWM1_CTRL = 0x0;
    return 0;
}



/* TMR */


int tmr_enable(unsigned int n){
    if(n<0) return -1;
    if(n==0) 
        *TMR0_EN = 0x1;
    else if (n==1)
        *TMR1_EN = 0x1;
        else if (n==2)
        *TMR2_EN = 0x1;
        else if (n==3)
        *TMR3_EN = 0x1;
    return 0;
}

int tmr_disable(unsigned int n){
    if(n<0) return -1;
    if(n==0) 
        *TMR0_EN = 0x0;
    else if (n==1)
        *TMR1_EN = 0x0;
        else if (n==2)
        *TMR2_EN = 0x0;
        else if (n==3)
        *TMR3_EN = 0x0;
    return 0;
}


int tmr_init(unsigned int n, unsigned int pre){
  if(n<0) return -1;
    if(n==0) {
        
        return ((*TMR0_STATUS)&0x1);
    } else if(n==1){
        
        return ((*TMR1_STATUS)&0x1);
    }
    else if(n==2){
        
        return ((*TMR2_STATUS)&0x1);
    }
    else if(n==3){
        
         return ((*TMR3_STATUS)&0x1);
    }
    return 0;
}

int set_comp  (unsigned int n, unsigned int comp)
{

if(n<0) return -1;
    if(n==0) {
        
        *TMR0_CMP  = comp;
    } else if(n==1){
        
        *TMR1_CMP = comp;
    }
    else if(n==2){
        
        *TMR2_CMP = comp;
    }
    else if(n==3){
        
        *TMR3_CMP = comp;
    }
    return 0;

}

unsigned int get_tmr(unsigned int n){

if(n<0) return -1;
    if(n==0) {
        
        return *TMR0;
    } else if(n==1){
        
        return *TMR1;
    }
    else if(n==2){
        
        return *TMR2;
    }
    else if(n==3){
        
        return *TMR3;
    }
    return 0;


}



int get_tmr_status(unsigned int n){

if(n<0) return -1;
    if(n==0) {
        
        return *TMR0;
    } else if(n==1){
        
        return *TMR1;
    }
    else if(n==2){
        
        return *TMR2;
    }
    else if(n==3){
        
        return *TMR3;
    }
    return 0;


}

int tmr_im  (unsigned int n, unsigned int im)
{

if(n<0) return -1;
    if(n==0) {
        
        *TMR0_IM  = im;
    } else if(n==1){
        
        *TMR1_IM  = im;
    }
    else if(n==2){
        
        *TMR2_IM  = im;
    }
    else if(n==3){
        
        *TMR3_IM  = im;
    }
    return 0;

}


/* WDT */

int wdt_enable(unsigned int n){
    if(n>1) return -1;
    if(n==0) 
        *WDT0_WDEN = 0x1;
    else
        *WDT1_WDEN = 0x1;
    return 0;
}

int wdt_disable(unsigned int n){
    if(n>1) return -1;
    if(n==0) 
        *WDT0_WDEN = 0x0;
    else
        *WDT1_WDEN = 0x0;
    return 0;
}

int wdt_load (unsigned int n, unsigned int load_value){
    if(n>1) return -1;
    if(n==0) 
        *WDT0_WDLOAD = load_value;
    else
        *WDT0_WDLOAD = load_value;
    return 0;
}

int wdt_irqen (unsigned int n, unsigned int enable){
    if(n>1) return -1;
    if(n==0) 
        *WDT0_IRQEN = enable;
    else
        *WDT1_IRQEN = enable;
    return 0;
}

unsigned int get_wdtmr(unsigned int n){
    if(n>1) return -1;
    if(n==0) 
        return *WDT0_WDTMR;
    else
        return *WDT1_WDTMR;
}

unsigned int get_wdov(unsigned int n){
    if(n>1) return -1;
    if(n==0) 
        return *WDT0_WDOV;
    else
        return *WDT1_WDOV;
}

// ML Accelerator

void ML_ACC(unsigned int valid,  unsigned int sum0, unsigned int sum1, unsigned int sum2, unsigned int sum3, unsigned int a, unsigned int w0, unsigned int w1, unsigned int w2, unsigned int w3 )
{

  *ML_valid = valid; 
  
  *ML_sum0 = sum0;
  *ML_sum1 = sum1;
  *ML_sum2 = sum2;
  *ML_sum3 = sum3;
  *ML_a = a;
  *ML_w0 = w0;
  *ML_w1 = w1;
  *ML_w2 = w2;
  *ML_w3 = w3;

  
  
  
  
  
  

}

int read_out0()
{
  return *ML_out0 ;
}

int read_out1()
{
  return *ML_out1 ;
}

int read_out2()
{
  return *ML_out2 ;
}

int read_out3()
{
  return *ML_out3 ;
}


void SEC_ACC(unsigned int a, unsigned int b, unsigned int c)
{

  *SEC_in1 = a;
  *SEC_in2 = b;
  *SEC_in3 = c;
  
  
  

}
	
 inline int Tanh(unsigned int a)
{

  *Tanh_in = a;
  
return *Tanh_out ;
}

/*
inline int read_Tanh()
{
  return *Tanh_out ;
}
*/


void Sigmoid(unsigned int a)
{

  *Sig_in = a;
  

}
int read_Sigmoid()
{
  return *Sig_out ;
}



int read_SEC()
{
  return *SEC_out ;
}









