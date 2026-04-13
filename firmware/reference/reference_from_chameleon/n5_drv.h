
/* GPIO */
void gpio_set_dir(unsigned int );
void gpio_write(unsigned int );
unsigned int gpio_read(); 
void gpio_pull (unsigned char );
void gpio_im(unsigned int );

/* UART */
int uart_init(unsigned int , unsigned int );
int uart_puts(unsigned int , unsigned char *, unsigned int );
int uart_gets(unsigned int , unsigned char *, unsigned int );

/* SPI */
int spi_init(unsigned int , unsigned char , unsigned char , unsigned char );
unsigned int spi_status(unsigned int );
unsigned char spi_read(unsigned int );
int spi_write(unsigned int , unsigned char );
int spi_start(unsigned int );
int spi_end(unsigned int );

/* i2c */
int i2c_init(unsigned int , unsigned int );
int i2c_send(unsigned int , unsigned char , unsigned char );

/* PWM */
int pwm_init(unsigned int, unsigned int, unsigned int, unsigned int);
int pwm_enable(unsigned int);
int pwm_disable(unsigned int);

// ACC
//inline void dummy(unsigned int a, unsigned int b);
void ML_ACC(unsigned int valid, unsigned int sum0, unsigned int sum1, unsigned int sum2, unsigned int sum3, unsigned int a, unsigned int w0, unsigned int w1, unsigned int w2, unsigned int w3 );
int read_out0();
int read_out1();
int read_out2();
int read_out3();
int read_SEC();
void SEC_ACC(unsigned int a, unsigned int b, unsigned int c);
int Tanh(unsigned int);


