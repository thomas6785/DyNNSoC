#include "n5_drv.h"
#include "n5_int.h"
#include <stdint.h>
#include <stdio.h>
#include <unistd.h>

#define q7_t int8_t
#define q15_t int16_t
#define q31_t int32_t
#define q63_t int64_t

#define NNOM_TRUNCATE 
#ifndef NNOM_TRUNCATE 
 #define NN_ROUND(out_shift) ((0x1 << out_shift) >> 1 )
#else
 #define NN_ROUND(out_shift) 0
#endif
#define MAX(A, B) ((A) > (B) ? (A) : (B))

#define MIN(A, B) ((A) < (B) ? (A) : (B))



void local_convolve_HWC_q7_nonsquare(const q7_t *Im_in,                // input image
    const uint16_t dim_im_in_x,                                        // input image dimention x
    const uint16_t dim_im_in_y,                                        // input image dimention y
    const uint16_t ch_im_in,                                           // number of input image channels
    const q7_t *wt,                                                    // kernel weights
    const uint16_t ch_im_out,                                          // number of filters, i.e., output image channels
    const uint16_t dim_kernel_x,                                       // filter kernel size x
    const uint16_t dim_kernel_y,                                       // filter kernel size y
    const uint16_t padding_x,                                          // padding sizes x
    const uint16_t padding_y,                                          // padding sizes y
    const uint16_t stride_x,                                           // stride x
    const uint16_t stride_y,                                           // stride y
    const uint16_t dilation_x,                                         // dilation x
    const uint16_t dilation_y,                                         // dilation y
    const q7_t *bias,                                                  // bias
   // const nnom_qformat_param_t *bias_shift,                                        // bias shifts
    //const nnom_qformat_param_t *out_shift,                                         // output shift
   // const nnom_qtype_t q_type,                                         // per channel or per tensor
    q7_t *Im_out,                                                      // output image
    const uint16_t dim_im_out_x,                                       // output image dimension x
    const uint16_t dim_im_out_y,                                       // output image dimension y
    q15_t *bufferA,                                                    //buffer space for input
    q7_t *bufferB                                                      //buffer space for output
)
{
    *(int *)  (Im_in + (dim_im_in_x * dim_im_in_y * ch_im_in) )= 0;
    int i, j, k, l, m, n;
    int conv_out, conv_out2, conv_out3, conv_out4;
    int in_row, in_col;
    int in_pix_loc, wt_loc;
    int shift_idx, shift_steps;
    shift_steps = 0;
   /* if(q_type == NNOM_QTYPE_PER_AXIS)
        shift_steps = 1;
    else
        shift_steps = 0;
*/
  for (i = 0; i < ch_im_out/4; i++)
    {
       
        for (j = 0; j < dim_im_out_y; j++)
        {
            int32_t base_idx_y = stride_y * j - padding_y;
            for (k = 0; k < dim_im_out_x; k++)
            {
                int32_t base_idx_x = stride_x * k - padding_x;
                int32_t ker_y_start = MAX(0, -(base_idx_y-(dilation_y-1))/dilation_y);
                int32_t ker_x_start = MAX(0, -(base_idx_x-(dilation_x-1))/dilation_x);
                int32_t ker_y_end = MIN(dim_kernel_y, (dim_im_in_y - base_idx_y + (dilation_y-1))/dilation_y);
                int32_t ker_x_end = MIN(dim_kernel_x, (dim_im_in_x - base_idx_x + (dilation_x-1))/dilation_x);
                conv_out = bias[4*i];
                conv_out2 = bias [4*i +1];
                conv_out3 = bias [4*i +2];
                conv_out4 =  bias [4*i +3];

                
                for (m = ker_y_start; m < ker_y_end; m++)
                {
                    in_row = stride_y * j + m * dilation_y - padding_y;
                    in_col = stride_x * k + ker_x_start   - padding_x;
                    //cout << "ker x_start = " << ker_x_start << endl;
                    //cout << "ker x_end = " << ker_x_end << endl;
                    int max = ((ker_x_end-ker_x_start ) * ch_im_in);
                    in_pix_loc =  (in_row * dim_im_in_x + in_col) * ch_im_in ;
                    wt_loc = 4*i * ch_im_in * dim_kernel_y * dim_kernel_x + (m * dim_kernel_x + ker_x_start) * ch_im_in;
                    int w2_index = (4*i +1) * ch_im_in * dim_kernel_y * dim_kernel_x + (m * dim_kernel_x + ker_x_start) * ch_im_in;
                    int w3_index = (4*i +2) * ch_im_in * dim_kernel_y * dim_kernel_x + (m * dim_kernel_x + ker_x_start) * ch_im_in;
                    int w4_index = (4*i +3) * ch_im_in * dim_kernel_y * dim_kernel_x + (m * dim_kernel_x + ker_x_start) * ch_im_in;
                    
                    
                    int A = *(int *)(Im_in + in_pix_loc );
                    int B = *(int *) (wt + wt_loc);
                    int C = *(int *) (wt + w2_index);
                    int D = *(int *) (wt + w3_index);
                    int E = *(int *) (wt + w4_index);
                    //cout << "conv_out = " << conv_out << endl;
                   // conv_out = mac( conv_out, A, B, 4);
                   // parallel_four_mac (A, B, C, D, E, 4, &conv_out, &conv_out2, &conv_out3, &conv_out4);
                    ML_ACC(4,  conv_out, conv_out2, conv_out3, conv_out4, A,  B, C,D, E );
                    conv_out = read_out0();
                    conv_out2 = read_out1();
                    conv_out3 = read_out2();
                    conv_out4 = read_out3();
                     /*
                     uart_puts(0, "Done\n", 5);
                     num_print(conv_out);
                     uart_puts(0, "\n", 1);
                    */
                    for (int x = 1; x <  max/4 ; x++)
                    {


                        // pre-calculate the pixel location and weight location to improve the performance.


                        in_pix_loc =  in_pix_loc + 4;
                        wt_loc = wt_loc + 4;
                        w2_index = w2_index + 4;
                        w3_index = w3_index + 4;
                        w4_index = w4_index + 4;
                        
                       // cout << "Im[ " << in_pix_loc << "] * wt[" << wt_loc << endl;
                        
                        //conv_out += Im_in[in_pix_loc] * wt[wt_loc];
                        
                        int A = *(int *)(Im_in + in_pix_loc );
                        int B = *(int *) (wt + wt_loc);
                        int C = *(int *) (wt + w2_index);
                        int D = *(int *) (wt + w3_index);
                        int E = *(int *) (wt + w4_index);
                        //cout << "conv_out = " << conv_out << endl;
                       // conv_out = mac( conv_out, A, B, 4);
                        
                     ML_ACC(4, conv_out, conv_out2, conv_out3, conv_out4, A,  B, C,D, E );
                    conv_out = read_out0();
                    conv_out2 = read_out1();
                    conv_out3 = read_out2();
                    conv_out4 = read_out3();
                    /*
                    uart_puts(0, "Done\n", 5);
                     num_print(conv_out);
                     uart_puts(0, "\n", 1);
                     */
                       
                    }
                    int r = max & 0x03;
                    if ( r > 0)
                    {
                        //cout << "r = " << r << endl;
                        in_pix_loc =  in_pix_loc + 4;
                         wt_loc = wt_loc + 4;
                        w2_index = w2_index + 4;
                        w3_index = w3_index + 4;
                        w4_index = w4_index + 4;
                    
                        // cout << "Im[ " << in_pix_loc << "] * wt[" << wt_loc << endl;
                         
                        int A = *(int *)(Im_in + in_pix_loc );
                        int B = *(int *) (wt + wt_loc);
                        int C = *(int *) (wt + w2_index);
                        int D = *(int *) (wt + w3_index);
                        int E = *(int *) (wt + w4_index);
                      //  cout << "conv_out = " << conv_out << endl;
                        //conv_out = mac( conv_out, A, B, r);
                        //cout << "conv_out = " << conv_out << endl;
                        //parallel_four_mac (A, B, C, D, E, r, &conv_out, &conv_out2, &conv_out3, &conv_out4);
                    ML_ACC(r, conv_out, conv_out2, conv_out3, conv_out4, A,  B, C,D, E );
                    conv_out = read_out0();
                    conv_out2 = read_out1();
                    conv_out3 = read_out2();
                    conv_out4 = read_out3();
                    /*
                    uart_puts(0, "Done\n", 5);
                     num_print(conv_out);
                     uart_puts(0, "\n", 1);
                     */
                    }
                
                   
                }

                Im_out[4*i + (j * dim_im_out_x + k) * ch_im_out] = conv_out;
                Im_out[(4*i+1) + (j * dim_im_out_x + k) * ch_im_out] = conv_out2;
                Im_out[(4*i+2) + (j * dim_im_out_x + k) * ch_im_out] = conv_out3;
                Im_out[(4*i+3) + (j * dim_im_out_x + k) * ch_im_out] = conv_out4;

               // cout << "Im_out [ " <<(4*i) + (j * dim_im_out_x + k) * ch_im_out << "] = " << conv_out << endl;
               // cout << "Im_out [ " <<(4*i + 1) + (j * dim_im_out_x + k) * ch_im_out << "] = " << conv_out2 << endl;
                //cout << "Im_out [ " <<(4*i + 2) + (j * dim_im_out_x + k) * ch_im_out << "] = " << conv_out3 << endl;
                //cout << "Im_out [ " <<(4*i + 3) + (j * dim_im_out_x + k) * ch_im_out << "] = " << conv_out4 << endl;




            }
        }
    }
  
    int r = ch_im_out & 0x03;
    if ( r > 0)
    {
       
        if ( r == 1)
        {
            for (j = 0; j < dim_im_out_y; j++)
            {
                int32_t base_idx_y = stride_y * j - padding_y;
                for (k = 0; k < dim_im_out_x; k++)
                {
                    int32_t base_idx_x = stride_x * k - padding_x;
                    int32_t ker_y_start = MAX(0, -(base_idx_y-(dilation_y-1))/dilation_y);
                    int32_t ker_x_start = MAX(0, -(base_idx_x-(dilation_x-1))/dilation_x);
                    int32_t ker_y_end = MIN(dim_kernel_y, (dim_im_in_y - base_idx_y + (dilation_y-1))/dilation_y);
                    int32_t ker_x_end = MIN(dim_kernel_x, (dim_im_in_x - base_idx_x + (dilation_x-1))/dilation_x);
                    conv_out = bias[ch_im_out -1];
                    conv_out2 = 0;
                    conv_out3 = 0;
                    conv_out4 = 0;

                    
                    for (m = ker_y_start; m < ker_y_end; m++)
                    {
                        in_row = stride_y * j + m * dilation_y - padding_y;
                        in_col = stride_x * k + ker_x_start   - padding_x;
                        //cout << "ker x_start = " << ker_x_start << endl;
                        //cout << "ker x_end = " << ker_x_end << endl;
                        int max = ((ker_x_end-ker_x_start ) * ch_im_in);
                        in_pix_loc =  (in_row * dim_im_in_x + in_col) * ch_im_in ;
                        wt_loc = (ch_im_out-1)* ch_im_in * dim_kernel_y * dim_kernel_x + (m * dim_kernel_x + ker_x_start) * ch_im_in;
                       // int w2_index = (4*i +1) * ch_im_in * dim_kernel_y * dim_kernel_x + (m * dim_kernel_x + ker_x_start) * ch_im_in;
                       // int w3_index = (4*i +2) * ch_im_in * dim_kernel_y * dim_kernel_x + (m * dim_kernel_x + ker_x_start) * ch_im_in;
                       // int w4_index = (4*i +3) * ch_im_in * dim_kernel_y * dim_kernel_x + (m * dim_kernel_x + ker_x_start) * ch_im_in;
                        
                        
                        int A = *(int *)(Im_in + in_pix_loc );
                        int B = *(int *) (wt + wt_loc);
                        //int C = *(int *) (wt + w2_index);
                        //int D = *(int *) (wt + w3_index);
                        //int E = *(int *) (wt + w4_index);
                        //cout << "conv_out = " << conv_out << endl;
                       // conv_out = mac( conv_out, A, B, 4);
                        //parallel_four_mac (A, B,0, 0, 0, 4, &conv_out, &conv_out2, &conv_out3, &conv_out4);
                    ML_ACC(4, conv_out, conv_out2, conv_out3, conv_out4, A,  B, 0,0, 0 );
                    conv_out = read_out0();
                   // conv_out2 = read_out1();
                    //conv_out3 = read_out2();
                    //conv_out4 = read_out3();
                        
                        
                        for (int x = 1; x <  max/4 ; x++)
                        {


                            // pre-calculate the pixel location and weight location to improve the performance.


                            in_pix_loc =  in_pix_loc + 4;
                            wt_loc = wt_loc + 4;
                       
                           // cout << "Im[ " << in_pix_loc << "] * wt[" << wt_loc << endl;
                            
                            //conv_out += Im_in[in_pix_loc] * wt[wt_loc];
                            
                            int A = *(int *)(Im_in + in_pix_loc );
                            int B = *(int *) (wt + wt_loc);
                           // int D = *(int *) (wt + w3_index);
                            //int E = *(int *) (wt + w4_index);
                            //cout << "conv_out = " << conv_out << endl;
                           // conv_out = mac( conv_out, A, B, 4);
                            
                            //parallel_four_mac (A, B, 0, 0, 0, 4, &conv_out, &conv_out2, &conv_out3, &conv_out4);
                     ML_ACC(4, conv_out, conv_out2, conv_out3, conv_out4, A,  B, 0,0, 0 );
                    conv_out = read_out0();
                    conv_out2 = read_out1();
                           
                        }
                        int v = max & 0x03;
                        if ( v > 0)
                        {
                            //cout << "r = " << r << endl;
                            in_pix_loc =  in_pix_loc + 4;
                             wt_loc = wt_loc + 4;
                        
                            // cout << "Im[ " << in_pix_loc << "] * wt[" << wt_loc << endl;
                             
                            int A = *(int *)(Im_in + in_pix_loc );
                            int B = *(int *) (wt + wt_loc);
                            
                          //  cout << "conv_out = " << conv_out << endl;
                            //conv_out = mac( conv_out, A, B, r);
                            //cout << "conv_out = " << conv_out << endl;
                           // parallel_four_mac (A, B, 0, 0, 0, v, &conv_out, &conv_out2, &conv_out3, &conv_out4);
                     ML_ACC(4, conv_out, conv_out2, conv_out3, conv_out4, A,  B, 0,0, 0 );
                    conv_out = read_out0();
                   // conv_out2 = read_out1();
                   // conv_out3 = read_out2();
                    //conv_out4 = read_out3();
                        }
                    
                       
                    }

                    Im_out[(ch_im_out-1) + (j * dim_im_out_x + k) * ch_im_out] = conv_out;
                   // cout << "Im_out [ " << (ch_im_out-1) + (j * dim_im_out_x + k) * ch_im_out << "] = " << conv_out << endl;

                }
            }
        }
        else if ( r == 2)
        {
           // cout << " r = 2" << endl;
            for (j = 0; j < dim_im_out_y; j++)
            {
                int32_t base_idx_y = stride_y * j - padding_y;
                for (k = 0; k < dim_im_out_x; k++)
                {
                    int32_t base_idx_x = stride_x * k - padding_x;
                    int32_t ker_y_start = MAX(0, -(base_idx_y-(dilation_y-1))/dilation_y);
                    int32_t ker_x_start = MAX(0, -(base_idx_x-(dilation_x-1))/dilation_x);
                    int32_t ker_y_end = MIN(dim_kernel_y, (dim_im_in_y - base_idx_y + (dilation_y-1))/dilation_y);
                    int32_t ker_x_end = MIN(dim_kernel_x, (dim_im_in_x - base_idx_x + (dilation_x-1))/dilation_x);
                    conv_out = bias[ch_im_out -2];
                    conv_out2 = bias[ch_im_out -1];
                    conv_out3 = 0;
                    conv_out4 = 0;

                    
                    for (m = ker_y_start; m < ker_y_end; m++)
                    {
                        in_row = stride_y * j + m * dilation_y - padding_y;
                        in_col = stride_x * k + ker_x_start   - padding_x;
                        //cout << "ker x_start = " << ker_x_start << endl;
                        //cout << "ker x_end = " << ker_x_end << endl;
                        int max = ((ker_x_end-ker_x_start ) * ch_im_in);
                        in_pix_loc =  (in_row * dim_im_in_x + in_col) * ch_im_in ;
                        wt_loc = (ch_im_out-2) * ch_im_in * dim_kernel_y * dim_kernel_x + (m * dim_kernel_x + ker_x_start) * ch_im_in;
                        int w2_index = (ch_im_out-1) * ch_im_in * dim_kernel_y * dim_kernel_x + (m * dim_kernel_x + ker_x_start) * ch_im_in;
                       // int w3_index = (4*i +2) * ch_im_in * dim_kernel_y * dim_kernel_x + (m * dim_kernel_x + ker_x_start) * ch_im_in;
                        //int w4_index = (4*i +3) * ch_im_in * dim_kernel_y * dim_kernel_x + (m * dim_kernel_x + ker_x_start) * ch_im_in;
                        
                        
                        int A = *(int *)(Im_in + in_pix_loc );
                        int B = *(int *) (wt + wt_loc);
                        int C = *(int *) (wt + w2_index);
                        //int D = *(int *) (wt + w3_index);
                       // int E = *(int *) (wt + w4_index);
                        //cout << "conv_out = " << conv_out << endl;
                       // conv_out = mac( conv_out, A, B, 4);
                        //parallel_four_mac (A, B, C, 0, 0, 4, &conv_out, &conv_out2, &conv_out3, &conv_out4);
                     ML_ACC(4,  conv_out, conv_out2, conv_out3, conv_out4, A,  B, C,0, 0 );
                    conv_out = read_out0();
                    conv_out2 = read_out1();
                        
                        for (int x = 1; x <  max/4 ; x++)
                        {


                            // pre-calculate the pixel location and weight location to improve the performance.


                            in_pix_loc =  in_pix_loc + 4;
                            wt_loc = wt_loc + 4;
                            w2_index = w2_index + 4;
                            //w3_index = w3_index + 4;
                            //w4_index = w4_index + 4;
                       
                           // cout << "Im[ " << in_pix_loc << "] * wt[" << wt_loc << endl;
                            
                            //conv_out += Im_in[in_pix_loc] * wt[wt_loc];
                            
                            int A = *(int *)(Im_in + in_pix_loc );
                            int B = *(int *) (wt + wt_loc);
                            int C = *(int *) (wt + w2_index);
                            //int D = *(int *) (wt + w3_index);
                            //int E = *(int *) (wt + w4_index);
                            //cout << "conv_out = " << conv_out << endl;
                           // conv_out = mac( conv_out, A, B, 4);
                            
                            //parallel_four_mac (A, B, C, 0, 0, 4, &conv_out, &conv_out2, &conv_out3, &conv_out4);
                             ML_ACC(4,  conv_out, conv_out2, conv_out3, conv_out4, A,  B, C,0, 0 );
                    conv_out = read_out0();
                    conv_out2 = read_out1();
                    //conv_out3 = read_out2();
                    //conv_out4 = read_out3();
                           
                        }
                        int v = max & 0x03;
                        if ( v > 0)
                        {
                            //cout << "r = " << r << endl;
                            in_pix_loc =  in_pix_loc + 4;
                             wt_loc = wt_loc + 4;
                            w2_index = w2_index + 4;
                        
                            // cout << "Im[ " << in_pix_loc << "] * wt[" << wt_loc << endl;
                             
                            int A = *(int *)(Im_in + in_pix_loc );
                            int B = *(int *) (wt + wt_loc);
                            int C = *(int *) (wt + w2_index);
                            //int D = *(int *) (wt + w3_index);
                            //int E = *(int *) (wt + w4_index);
                          //  cout << "conv_out = " << conv_out << endl;
                            //conv_out = mac( conv_out, A, B, r);
                            //cout << "conv_out = " << conv_out << endl;
                            //parallel_four_mac (A, B, C, 0, 0, v, &conv_out, &conv_out2, &conv_out3, &conv_out4);
                     ML_ACC(v,  conv_out, conv_out2, conv_out3, conv_out4, A,  B, C,0, 0 );
                    conv_out = read_out0();
                    conv_out2 = read_out1();
                    //conv_out3 = read_out2();
                    //conv_out4 = read_out3();
                        }
                    
                       
                    }

                  
                    Im_out[(ch_im_out-2) + (j * dim_im_out_x + k) * ch_im_out] = conv_out;
                    Im_out[(ch_im_out-1) + (j * dim_im_out_x + k) * ch_im_out]= conv_out2;
                   // cout << "Im_out [ " << (ch_im_out-2)+ (j * dim_im_out_x + k) * ch_im_out << "] = " << conv_out << endl;
                    //cout << "Im_out [ " << (ch_im_out-1)+ (j * dim_im_out_x + k) * ch_im_out << "] = " << conv_out2<< endl;

                }
            }
        }
        else if (r == 3)
        {
            for (j = 0; j < dim_im_out_y; j++)
            {
                int32_t base_idx_y = stride_y * j - padding_y;
                for (k = 0; k < dim_im_out_x; k++)
                {
                    int32_t base_idx_x = stride_x * k - padding_x;
                    int32_t ker_y_start = MAX(0, -(base_idx_y-(dilation_y-1))/dilation_y);
                    int32_t ker_x_start = MAX(0, -(base_idx_x-(dilation_x-1))/dilation_x);
                    int32_t ker_y_end = MIN(dim_kernel_y, (dim_im_in_y - base_idx_y + (dilation_y-1))/dilation_y);
                    int32_t ker_x_end = MIN(dim_kernel_x, (dim_im_in_x - base_idx_x + (dilation_x-1))/dilation_x);
                    conv_out = bias[ch_im_out -3];
                    conv_out2 = bias[ch_im_out -2];
                    conv_out3 = bias[ch_im_out -1];
                    conv_out4 = 0;

                    
                    for (m = ker_y_start; m < ker_y_end; m++)
                    {
                        in_row = stride_y * j + m * dilation_y - padding_y;
                        in_col = stride_x * k + ker_x_start   - padding_x;
                        //cout << "ker x_start = " << ker_x_start << endl;
                        //cout << "ker x_end = " << ker_x_end << endl;
                        int max = ((ker_x_end-ker_x_start ) * ch_im_in);
                        in_pix_loc =  (in_row * dim_im_in_x + in_col) * ch_im_in ;
                        wt_loc =(ch_im_out-3)* ch_im_in * dim_kernel_y * dim_kernel_x + (m * dim_kernel_x + ker_x_start) * ch_im_in;
                        int w2_index = (ch_im_out-2) * ch_im_in * dim_kernel_y * dim_kernel_x + (m * dim_kernel_x + ker_x_start) * ch_im_in;
                        int w3_index = (ch_im_out-1) * ch_im_in * dim_kernel_y * dim_kernel_x + (m * dim_kernel_x + ker_x_start) * ch_im_in;
                       // int w4_index = (4*i +3) * ch_im_in * dim_kernel_y * dim_kernel_x + (m * dim_kernel_x + ker_x_start) * ch_im_in;
                        
                        
                        int A = *(int *)(Im_in + in_pix_loc );
                        int B = *(int *) (wt + wt_loc);
                        int C = *(int *) (wt + w2_index);
                        int D = *(int *) (wt + w3_index);
                        //int E = *(int *) (wt + w4_index);
                        //cout << "conv_out = " << conv_out << endl;
                       // conv_out = mac( conv_out, A, B, 4);
                       // parallel_four_mac (A, B, C, D, 0, 4, &conv_out, &conv_out2, &conv_out3, &conv_out4);
                     ML_ACC(4, conv_out, conv_out2, conv_out3, conv_out4, A,  B, C,D, 0 );
                    conv_out = read_out0();
                    conv_out2 = read_out1();
                    conv_out3 = read_out2();
                   // conv_out4 = read_out3();
                        for (int x = 1; x <  max/4 ; x++)
                        {


                            // pre-calculate the pixel location and weight location to improve the performance.


                            in_pix_loc =  in_pix_loc + 4;
                            wt_loc = wt_loc + 4;
                            w2_index = w2_index + 4;
                            w3_index = w3_index + 4;
                            //w4_index = w4_index + 4;
                       
                           // cout << "Im[ " << in_pix_loc << "] * wt[" << wt_loc << endl;
                            
                            //conv_out += Im_in[in_pix_loc] * wt[wt_loc];
                            
                            int A = *(int *)(Im_in + in_pix_loc );
                            int B = *(int *) (wt + wt_loc);
                            int C = *(int *) (wt + w2_index);
                            int D = *(int *) (wt + w3_index);
                           // int E = *(int *) (wt + w4_index);
                            //cout << "conv_out = " << conv_out << endl;
                           // conv_out = mac( conv_out, A, B, 4);
                            
                            //parallel_four_mac (A, B, C, D, 0, 4, &conv_out, &conv_out2, &conv_out3, &conv_out4);
                            ML_ACC(4, conv_out, conv_out2, conv_out3, conv_out4, A,  B, C,D, 0 );
                    conv_out = read_out0();
                    conv_out2 = read_out1();
                    conv_out3 = read_out2();
                   // conv_out4 = read_out3();
                        }
                        int v = max & 0x03;
                        if ( v > 0)
                        {
                            //cout << "r = " << r << endl;
                            in_pix_loc =  in_pix_loc + 4;
                             wt_loc = wt_loc + 4;
                            w2_index = w2_index + 4;
                            w3_index = w3_index + 4;
                           // w4_index = w4_index + 4;
                        
                            // cout << "Im[ " << in_pix_loc << "] * wt[" << wt_loc << endl;
                             
                            int A = *(int *)(Im_in + in_pix_loc );
                            int B = *(int *) (wt + wt_loc);
                            int C = *(int *) (wt + w2_index);
                            int D = *(int *) (wt + w3_index);
                           // int E = *(int *) (wt + w4_index);
                          //  cout << "conv_out = " << conv_out << endl;
                            //conv_out = mac( conv_out, A, B, r);
                            //cout << "conv_out = " << conv_out << endl;
                            //parallel_four_mac (A, B, C, D, 0, v, &conv_out, &conv_out2, &conv_out3, &conv_out4);
                     ML_ACC(4, conv_out, conv_out2, conv_out3, conv_out4, A,  B, C,D, 0 );
                    conv_out = read_out0();
                    conv_out2 = read_out1();
                    conv_out3 = read_out2();
                    //conv_out4 = read_out3();
                        }
                    
                       
                    }

                    Im_out[(ch_im_out-3) + (j * dim_im_out_x + k) * ch_im_out] = conv_out;
                    Im_out[(ch_im_out-2) + (j * dim_im_out_x + k) * ch_im_out] = conv_out2;
                    Im_out[(ch_im_out-1) + (j * dim_im_out_x + k) * ch_im_out] = conv_out3;
                    //cout << " Im_out[ " << (ch_im_out-3) + (j * dim_im_out_x + k) * ch_im_out << "] = " << signed (conv_out) << endl;
                    //cout << " Im_out[ " << (ch_im_out-2) + (j * dim_im_out_x + k) * ch_im_out << "] = " << signed (conv_out2) << endl;
                    //cout << " Im_out[ " << (ch_im_out-1) + (j * dim_im_out_x + k) * ch_im_out << "] = " << signed (conv_out3) << endl;

                }
            }
        }
    }

}


void num_print(long num){
    unsigned int base = 10;
    int sign_bit = 0;

    char string[20];
    char* end = string + 19;
    char* p   = end;
    *p = '\n';
    
    if (num < 0){
        num = 0 - num;
        sign_bit = 1;
    }

    do {
        *(--p) = (num % base) + '0';
        num /= base;
    } while (num);

    if (sign_bit)
        *(--p) = '-';
    
    size_t len = end - p;
   // write(1, p, len + 1);
    uart_puts(0,p, len + 1);
    
}


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



#define     DELAY(n)   for(int i=0; i<n; i++)

int main(){

 
    // Initialization
    uart_init (0, 0);
    uart_init (1, 0);
    gpio_set_dir(0x00FF);
    //spi_init(0, 0,0,20);
    //spi_init(1, 0,0,20);
    
   
    
    // GPIO
    uart_puts (0, "GPIO Test: ", 11);
    gpio_write(0x0055);
    DELAY(100);
    /*while (1){
    	gpio_write(0x0055);
    	DELAY(250000);
    	gpio_write(0x0000);
    }*/
    int gpio_data = gpio_read();
    if((gpio_data >> 8) == 0x55)
        uart_puts(0,"Passed!\n", 8);
    else
        uart_puts(0,"Failed!\n", 8);
    
    	//gpio_write (0x0033);
    
    uart_puts(0,"Yesss1!\n", 8);
    //gpio_write(0x0000);

    const q7_t Im_in[75] = { 2,1,0,

                             1,0,0,

                             1,2,0,

                             2,2,2,

                             2,1,0,


                             1,2,1,

                             2,2,1,

                             2,1,2,

                             2,1,2,

                             1,0,1,


                             0,0,1,

                             2,2,1,

                             2,1,1,

                             1,0,2,

                             0,2,1,


                             1,0,1,

                             0,1,0,

                             1,2,1,

                             2,2,2,

                             0,2,0,


                             0,1,0,

                             1,1,2,

                             1,2,0,

                             0,2,2,

                             1,2,2

                           };



        
	uart_puts(0,"Yesss2!\n", 8);
	//gpio_write(0x1111);
	

        

        

        /*

                         2,1,1,2,2,

                         1,2,2,2,1,

                         0,2,2,1,0,

                         1,0,1,2,0,

                         0,1,1,0,1,

        

                         1,0,2,2,1,

                         2,2,1,1,0,

                         0,2,1,0,2,

                         0,1,2,2,2,

                         1,1,2,2,2,

                         

                         0,0,0,2,0,

                         1,1,2,2,1,

                         1,1,1,2,1,

                         1,0,1,2,0,

                         0,2,0,2,2

    */

    const uint16_t dim_im_in_x = 5;

    const uint16_t dim_im_in_y = 5;

    const uint16_t ch_im_in = 3;

    const q7_t wt[108] = {

                          1,0,1,

                          0,0,-1,

                          -1,1,0,


                          0,0,-1,

                          0,-1,-1,

                          1,-1,-1,


                          1,1,1,

                          1,0,-1,

                          0,-1,-1,


                          0,-1,0,

                          0,-1,0,

                          1,-1,-1,


                          -1,0,-1,

                          -1,0,-1,

                          1,-1,1,


                          -1, -1, 0,

                          1, 1, -1,

                          -1, -1, 1,



        


        

        

                         1,0,1,
                        0,0,-1,
                        -1,1,0,

                        0,0,-1,
                        0,-1,-1,
                        1,-1,-1,

                        1,1,1,
                        1,0,-1,
                        0,-1,-1,

                        0,-1,0,
                        0,-1,0,
                        1,-1,-1,

                        -1,0,-1,
                        -1,0,-1,
                        1,-1,1,

                        -1, -1, 0,
                        1, 1, -1,
                        -1, -1, 1,
            
   };
   
   
   
   //gpio_write (0x2222);

      	uart_puts(0,"Yesss3!\n", 8);                

     const uint16_t ch_im_out = 4;

    const uint16_t dim_kernel_x = 3;

    const uint16_t dim_kernel_y =3;

    const uint16_t padding_x =1;

    const uint16_t padding_y = 1;

    const uint16_t stride_x = 2;

    const uint16_t stride_y = 2;

    const q7_t bias[4] = {1,0,0,0};

    const uint16_t bias_shift = 0;

    const uint16_t out_shift =0;



    const uint16_t dim_im_out_x = 3;

    const uint16_t dim_im_out_y = 3;
    
       uart_puts(0,"Yesss4!\n", 8);

    q7_t Im_out [ dim_im_out_x * dim_im_out_y *ch_im_out];
    
    //q7_t Im_out [ 36];

    q15_t *bufferA;

    q7_t *bufferB;


    const uint16_t dilation_x =1;

    const uint16_t dilation_y =1;


	uart_puts(0,"Yesss5!\n", 8);
	//gpio_write (0x0033);

    local_convolve_HWC_q7_nonsquare(Im_in, dim_im_in_x, dim_im_in_y, ch_im_in, wt, ch_im_out, dim_kernel_x, dim_kernel_y, padding_x, padding_y, stride_x, stride_y, dilation_x, dilation_y, bias, Im_out, dim_im_out_y, dim_im_out_y, bufferA, bufferB);
    
    //gpio_write (0x0044);
    	uart_puts(0,"Yesss6!\n", 8);
    //int n = dim_im_out_x * dim_im_out_y *ch_im_out;
    int n = 36;
    for (int i =0; i < n ; i++)
    
    {
        //cout << signed(Im_out [i])<<endl;
        num_print(Im_out [i]);
        uart_puts(0, "\n", 1);
    }

// Done!
    uart_puts(0, "Done!\n\n", 7);
    return 0;
}
 
    
 
