#include "n5_drv.h"
#include "n5_int.h"
#include <stdint.h>



//void SPI0_handler(void) __attribute__((interrupt));

void UART0_handler(void){

   gpio_write(0xFFFF);
}
void UART1_handler(void){

   gpio_write(0x1111);
}
void SPI0_handler(void){

   gpio_write(0x2222);
}
void SPI1_handler(void){

   gpio_write(0x3333);
}
void TMR0_handler(void){

   gpio_write(0x6666);
}
void TMR1_handler(void){

   gpio_write(0x7777);
}
void TMR2_handler(void){

   gpio_write(0x8888);
}
void TMR3_handler(void){

   gpio_write(0x9999);
}
void WDT0_handler(void){

   gpio_write(0xAAAA);
}
void WDT1_handler(void){

   gpio_write(0xBBBB);
}

void IRQ() {
    gpio_write(0x0099);        
}

int fact(int n){
    int f = 1;
    for(int i=2; i<=n; i++)
        f = f * i;
    return f;
}

int strlen(char *s){
    int i=0;
    while (*s){
        i++;
    }
    return i;
}

void M23LC_write_byte(int n, unsigned int addr, unsigned int data){
  spi_start(n);
  spi_write(n, 0x2);
  spi_write(n, addr >> 8);     // Address high byte
  spi_write(n, addr & 0xFF);   // Address low byte
  spi_write(n, data);
  spi_end(n);
}

unsigned char M23LC_read_byte(int n, unsigned short addr){
  spi_start(n);
  spi_write(n, 0x3);
  spi_write(n, addr >> 8);     // Address high byte
  spi_write(n, addr & 0xFF);   // Address low byte
  spi_write(n, 0);             // just write a dummy data to get the data out
  spi_end(n);
  return spi_read(n);
}

#define     DELAY(n)   for(int i=0; i<n; i++)

int main(){

 unsigned char temp[]={'A','B','C'};
 
    // Initialization
    uart_init (0, 0);
    uart_init (1, 0);
    gpio_set_dir(0x00FF);
    spi_init(0, 0,0,20);
    spi_init(1, 0,0,20);
    
    // Enable global interrupt 
    
    enable_global_interrupt();
    
    //enable cpu level interrupt
    /* IRQ 0: UART 0
       IRQ 1: UART 1
       IRQ 2: SPI 0
       IRQ 3: SPI 1
       IRQ 4: I2C 0
       IRQ 5: I2C 1
       IRQ 6: TMR 0
       IRQ 7: TMR 1
       IRQ 8: TMR 2
       IRQ 9: TMR 3
       IRQ 10: WDT 0
       IRQ 11: WDT 1*/
    
    enable_irq11();
    
    
    // enable peripheral level iterrupt mask
    
    //gpio_im (0xFF00);
    //uart_im (0, 0x03);
    //uart_im (1, 0x03);
    //spi_im (0, 0x1); 
    //spi_im (1, 0x1);
    //tmr_im(0, 0x1);
    //tmr_im(1, 0x1);
    //tmr_im(2, 0x1);
    //tmr_im(3, 0x1);
    //wdt_irqen(0, 0x1); 
    wdt_irqen(1, 0x1); 
    
    // start UART test 
    // UART0
    uart_puts (0, "UART 1!\n", 8);
    uart_gets(0, temp, 8);  // not working "hanging"
   uart_puts(0,&temp[0],8);
    
    //UART1
    
    uart_puts (1, "UART 2!\n", 8);
    
    
    // start I2C Test 
    //I2C0
    
    
    
    //I2C1
    
    DELAY(100);
    uart_puts (0, "TMR Test\n", 9);
    // Start TMR1
    tmr_enable(0);
    tmr_init(0,0);
    set_comp(0,250);
    // Start TMR2
    tmr_enable(1);
    tmr_init(1,0);
    set_comp(1,200);
    // Start TMR3
     tmr_enable(2);
    tmr_init(2,0);
    set_comp(2,20);
    tmr_disable(2);
    // Start TMR4
     tmr_enable(3);
    tmr_init(3,0);
    set_comp(3,50);
    tmr_disable(3);
    
    // Start the test
    
    
    // GPIO
    uart_puts (0, "GPIO Test: ", 11);
    gpio_write(0x0055);
    DELAY(100);
    int gpio_data = gpio_read();
    if((gpio_data >> 8) == 0x55)
        uart_puts(0,"Passed!\n", 8);
    else
        uart_puts(0,"Failed!\n", 8);
    
    //uart_puts (0, "GPIO Test 2: ", 13);
    //DELAY(100);
    //gpio_set_dir(0xFFFF);
    gpio_write(0x0012);
    DELAY(100);
    gpio_data = gpio_read();
    if(gpio_data == 0x0012)
        uart_puts(0,"Passed!\n", 8);
    else
        uart_puts(0,"Failed!\n", 8);
    
    
    // External SPM Accelerator
    uart_puts (0, "SPM Test: ", 9);
    int factorial = fact(5);
    DELAY(100);
    if(factorial==120)
        uart_puts(0,"Passed!\n", 8);
    else 
        uart_puts(0,"Failed!\n", 8);

    // SPI 0
    	
    uart_puts (0, "SPI Test: ", 9);
    M23LC_write_byte(0, 0, 0xA5);
    unsigned int spi_data = M23LC_read_byte(0, 0);
    DELAY(100);
    if(spi_data==0xA5)
        uart_puts(0,"Passed!\n", 8);
    else 
        uart_puts(0,"Failed!\n", 8);
    
    //gpio_write(0x0005); 
    //DELAY (100);

    //SPI 1
    
    /*uart_puts (0, "SPI Test 2: ", 11);
    M23LC_write_byte(1, 10, 0x12);
    unsigned int spi_d = M23LC_read_byte(1, 10);
    DELAY(100);
    if(spi_d==0x12)
    	uart_puts(0,"Passed!\n", 8);
    else 
        uart_puts(0,"Failed!\n", 8);*/


    // PWM 0
    uart_puts (0, "PWM Test\n", 9);
    pwm_init(0, 250, 100, 4);
 	pwm_enable(0);
    DELAY(300);
    pwm_disable(0); 
    
    // PWM 1
    pwm_init(1, 250, 100, 4);
 	pwm_enable(1);
    DELAY(300);
    pwm_disable(1);
    
    //WDT 0
    uart_puts (0, "WDT Test\n", 9);
    wdt_load (0, 0x10);
    wdt_enable(0);
    //DELAY(300);
    wdt_disable(0); 
    
    //WDT 1
    wdt_load (1, 0xA);
    wdt_enable(1);
    //DELAY(300);
    wdt_disable(1); 

    // Some Delay
    DELAY(100);
   
    
    // ML acc test
    
    int num1 = 0x01020304;
    int num2 = 0x01020304;
    
    
   //uint8_t A [4]={1,2,3,4};
   //uint8_t B [4]={1,2,3,4};
   int sum =0;
   int n=0;
  /* 
   gpio_write(0x0001); 
   ML_ACC(sum,num1,num2);
   //sum+= A[0]*B[0]+ A[1]*B[1]+ A[2]*B[2]+ A[3]*B[3];
   gpio_write(0x0002);
   n=read_dummy();
   
    if (n==30)
    {
    DELAY(100);
    uart_puts(0,"ML ACC Passed!\n", 15);
    }
    else {
    DELAY(100);
    uart_puts(0,"ML ACC Failed!\n", 15);
    
    }
    */
    // Done!
    uart_puts(0, "Done!\n\n", 7);
    
    return 0;
}
