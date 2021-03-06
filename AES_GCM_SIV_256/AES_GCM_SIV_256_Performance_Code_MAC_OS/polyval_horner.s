###############################################################################
# AES-GCM-SIV developers and authors:                                         #
#                                                                             #
# Shay Gueron,    University of Haifa, Israel and                             #
#                 Intel Corporation, Israel Development Center, Haifa, Israel #
# Adam Langley,   Google                                                      #
# Yehuda Lindell, Bar Ilan University                                         #
###############################################################################
#                                                                             #
# References:                                                                 #
#                                                                             #
# [1] S. Gueron, Y. Lindell, GCM-SIV: Full Nonce Misuse-Resistant             #
# Authenticated Encryption at Under One Cycle per Byte,                       #
# 22nd ACM Conference on Computer and Communications Security,                #
# 22nd ACM CCS: pages 109-119, 2015.                                          #
# [2] S. Gueron, A. Langley, Y. Lindell, AES-GCM-SIV: Nonce Misuse-Resistant  #
# Authenticated Encryption.                                                   #
# https://tools.ietf.org/html/draft-gueron-gcmsiv-02#                         #
###############################################################################
#                                                                             #
###############################################################################
#                                                                             #
# Copyright (c) 2016, Shay Gueron                                             #
#                                                                             #
#                                                                             #
# Permission to use this code for AES-GCM-SIV is granted.                     #
#                                                                             #
# Redistribution and use in source and binary forms, with or without          #
# modification, are permitted provided that the following conditions are      #
# met:                                                                        #
#                                                                             #
# * Redistributions of source code must retain the above copyright notice,    #
#   this list of conditions and the following disclaimer.                     #
#                                                                             #
# * Redistributions in binary form must reproduce the above copyright         #
#   notice, this list of conditions and the following disclaimer in the       #
#   documentation and/or other materials provided with the distribution.      #
#                                                                             #
# * The names of the contributors may not be used to endorse or promote       #
# products derived from this software without specific prior written          #
# permission.                                                                 #
#                                                                             #
###############################################################################
#                                                                             #
###############################################################################
# THIS SOFTWARE IS PROVIDED BY THE AUTHORS ""AS IS"" AND ANY                  #
# EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE           #
# IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR          #
# PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL INTEL CORPORATION OR              #
# CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL,       #
# EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO,         #
# PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR          #
# PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF      #
# LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING        #
# NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS          #
# SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.                #
###############################################################################


#.align  16
ONE:
.quad 1,0
TWO:
.quad 2,0
.Lbswap_mask:
.byte 15,14,13,12,11,10,9,8,7,6,5,4,3,2,1,0
shuff_mask:
.quad 0x0f0f0f0f0f0f0f0f, 0x0f0f0f0f0f0f0f0f
poly:
.quad 0x1, 0xc200000000000000 


#####################
#Used by _GFMUL     #
#.set RES, %xmm0        #
#.set H, %xmm1      #
#.set TMP1, %xmm2   #
#.set TMP2, %xmm3   #
#.set TMP3, %xmm4   #
#.set TMP4, %xmm5   #
#################################################################
# RES = _GFMUL(RES, H)
# a = RES
# b = H - remains unchanged
# res = RES
# uses also TMP1,TMP2,TMP3,TMP4
# __m128i _GFMUL(__m128i A, __m128i B);
#.type _GFMUL,@function
.globl _GFMUL
_GFMUL:  
    vpclmulqdq  $0x00, %xmm1, %xmm0, %xmm2
    vpclmulqdq  $0x11, %xmm1, %xmm0, %xmm5
    vpclmulqdq  $0x10, %xmm1, %xmm0, %xmm3
    vpclmulqdq  $0x01, %xmm1, %xmm0, %xmm4
    vpxor       %xmm4, %xmm3, %xmm3
    vpslldq     $8, %xmm3, %xmm4
    vpsrldq     $8, %xmm3, %xmm3
    vpxor       %xmm4, %xmm2, %xmm2
    vpxor       %xmm3, %xmm5, %xmm5

    vpclmulqdq  $0x10, poly(%rip), %xmm2, %xmm3
    vpshufd     $78, %xmm2, %xmm4
    vpxor       %xmm4, %xmm3, %xmm2
        
    vpclmulqdq  $0x10, poly(%rip), %xmm2, %xmm3
    vpshufd     $78, %xmm2, %xmm4
    vpxor       %xmm4, %xmm3, %xmm2

    vpxor       %xmm5, %xmm2, %xmm0
    ret
#.size _GFMUL, .-_GFMUL




#.set T, %rdi
#.set Hp, %rsi
#.set INp, %rdx
#.set L, %rcx
#
#.set LOC, %r10
#.set LEN, %eax

#void   Polyval_Horner(unsigned char T[16],         // output 
#                       const unsigned char* H, // H
#                       unsigned char* BUF,     // Buffer
#                       unsigned int blocks);       // LEn2
            
            
.globl _Polyval_Horner
_Polyval_Horner:

# parameter 1: %rdi     T       - pointers to POLYVAL output
# parameter 2: %rsi     Hp      - pointer to H (user key)
# parameter 3: %rdx     INp     - pointer to input
# parameter 4: %rcx     L       - total number of blocks in input BUFFER
    
        
    test  %rcx, %rcx
    jnz   .LbeginPoly
    ret
    
.LbeginPoly:    
    #We will start with L _GFMULS for POLYVAL(BIG_BUFFER)
    #%xmm0 = _GFMUL(%xmm0, %xmm1)
    
    pushq %rdi
    pushq %rsi
    pushq %rdx
    pushq %rcx
    pushq %r10  
    xor         %r10, %r10 
    shl         $4, %rcx                        #L contains number of bytes to proceed
    
    vmovdqu     (%rsi), %xmm1                       
    vmovdqu     (%rdi), %xmm0
    
.Lloop:

    vpxor       (%rdx,%r10), %xmm0, %xmm0           #%xmm0 = %xmm0 + Xi
    call _GFMUL                             #%xmm0 = %xmm0 * H
    add     $16, %r10
    cmp     %r10, %rcx
    jne   .Lloop
    #calculation of T is over here. %xmm0=T
    vmovdqu %xmm0, (%rdi)   
    popq %r10
    popq %rcx
    popq %rdx
    popq %rsi
    popq %rdi   
    ret

    
