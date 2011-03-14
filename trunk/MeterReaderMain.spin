'' Copyright (c) 2011 Jay Kickliter, Frank Lynum
'' Released under MIT license, see end of file for terms of use

CON
  _CLKMODE                            = XTAL1 + PLL16X
  _XINFREQ                            = 5_000_000

  ADC_CLK_PIN                         = 4               'SPI Prop -> ADC pin
  ADC_DIN_PIN                         = 5               'SPI ADC  -> Prop data pin
  ADC_DO_PIN                          = 6               'SPI Prop -> ADC data pin
  ADC_DS_PIN                          = 7               'SPI Prop -> ADC chip select pin

  DEBUG_PORT                          = 1               'Arbitray 1-4 port numbe for debug serial line
  DEBUG_TX_PIN                        = 30              'Prop->Computer data pin
  DEBUG_BAUD                          = 9600

  XBEE_PORT                           = 2               'Arbitray 1-4 port numbe for XBee serial line
  XBEE_TX_PIN                         = 27
  XBEE_RX_PIN                         = 26
  XBEE_BAUD                           = 57600
  XBEE_REMOTE_ADDRESS_UPPER_32_BITS   = $00_13_A2_00
  XBEE_REMOTE_ADDRESS_LOWER_32_BITS   = $40_4B_22_71
  XBEE_NETWORK_16_BIT_ADDRESS         = $FF_FE

  TELEMETRY_REPORTRING_FREQUENCY      = 1
  WAVEFORM_REPORTRING_FREQUENCY       = 1

  BUFFER_LENGTH                       = 100

  TIME_STEP                           = 13333
  ADC_CHANNEL_0_OFFSET                = 2061
  ADC_CHANNEL_1_OFFSET                = 2049




VAR
  long  channelState[8]
  long  channelValue[8]
  long  channelMax[8]
  long  channelMin[8]

  word  currentBuffer[BUFFER_LENGTH]
  word  tempCurrentBuffer[BUFFER_LENGTH]
  word  voltageBuffer[BUFFER_LENGTH]

  long  RMS[8]

  long  telemetryTransmitStack[50]
  long  energy
  long  voltAmps
  byte  telemetryBuffer[100]




OBJ
  uarts :       "pcFullDuplexSerial4FC"
  ADC   :       "ADC_INPUT_DRIVER"
  xbee  :       "XBee64Bit"




PUB main
  currentPtr    := @channelValue[3]
  voltagePtr    := @channelValue[0]
  currentBufPtr := @currentBuffer
  voltageBufPtr := @voltageBuffer
  currentRMSPtr := @RMS[0]
  voltageRMSPtr := @RMS[1]
  buffMax       := @currentBuffer[BUFFER_LENGTH]
  energyPtr     := @energy
  voltAmpsPtr   := @voltAmps

  uarts.init
  uarts.addPort(DEBUG_PORT, UARTS#PINNOTUSED, DEBUG_TX_PIN, UARTS#PINNOTUSED, UARTS#PINNOTUSED, UARTS#DEFAULTTHRESHOLD, UARTS#NOMODE, DEBUG_BAUD)
  uarts.addPort(XBEE_PORT, XBEE_RX_PIN, XBEE_TX_PIN, UARTS#PINNOTUSED, UARTS#PINNOTUSED, UARTS#DEFAULTTHRESHOLD, UARTS#NOMODE, XBEE_BAUD)
  uarts.start
  xbee.initialize(XBEE_PORT)
  ADC.start_pointed(ADC_DO_PIN, ADC_DIN_PIN, ADC_CLK_PIN, ADC_DS_PIN, 4, 4, 12, 1, @channelState, @channelValue, @channelMax, @channelMin)
  cognew(@meter_engine, @channelValue)
  cognew(telemetryTransmitLoop, @telemetryTransmitStack)




PUB reportRawADCValues | delay
  delay := cnt
  repeat
    uarts.decf(DEBUG_PORT, channelValue[0], 4)
    uarts.str(DEBUG_PORT, string("    "))
    uarts.decf(DEBUG_PORT, channelValue[1], 4)
    uarts.str(DEBUG_PORT, string("    "))
    uarts.decf(DEBUG_PORT, channelValue[2], 4)
    uarts.str(DEBUG_PORT, string("    "))
    uarts.decf(DEBUG_PORT, channelValue[3], 4)
    uarts.str(DEBUG_PORT, string("    "))
    uarts.decf(DEBUG_PORT, channelValue[4], 4)
    uarts.str(DEBUG_PORT, string("    "))
    uarts.decf(DEBUG_PORT, channelValue[5], 4)
    uarts.str(DEBUG_PORT, string("    "))
    uarts.decf(DEBUG_PORT, channelValue[6], 4)
    uarts.str(DEBUG_PORT, string("    "))
    uarts.decf(DEBUG_PORT, channelValue[7], 4)
    uarts.newline(DEBUG_PORT)
    waitcnt(delay += 80_000_000/3)





PUB reportBuffers | i
  waitcnt(cnt + clkfreq/10)
  uarts.str(1, string("I = ["))
  uarts.newline(1)
  repeat i from 0 to BUFFER_LENGTH - 1
    uarts.dec(DEBUG_PORT, currentBuffer[i])
    uarts.newline(DEBUG_PORT)
    waitcnt(cnt+clkfreq/100)
  uarts.str(1, string("]"))
  uarts.newline(1)
  uarts.newline(1)
  uarts.str(1, string("V = ["))
  uarts.newline(1)
  repeat i from 0 to BUFFER_LENGTH - 1
    uarts.dec(DEBUG_PORT, voltageBuffer[i])
    uarts.newline(DEBUG_PORT)
    waitcnt(cnt+clkfreq/100)
  uarts.str(1, string("]"))




PUB telemetryTransmitLoop | lastValuesTime , lastWaveformTime , valuesPeriod , waveformPeriod, lastWaveform
  lastWaveformTime := cnt
  lastValuesTime   := cnt
  valuesPeriod     := clkfreq/TELEMETRY_REPORTRING_FREQUENCY
  waveFormPeriod   := 2*clkfreq

  repeat
    if (cnt-valuesPeriod) > lastValuesTime
      telemetryBuffer[0] := "r"
      byteMove(@telemetryBuffer[1], @channelValue[3], 4)
      byteMove(@telemetryBuffer[5], @channelValue[0], 4)
      byteMove(@telemetryBuffer[9], @rms, 8)
      byteMove(@telemetryBuffer[17], @energy, 4)
      byteMove(@telemetryBuffer[21], @voltAmps, 4)
      xbee.apiArray(XBEE_REMOTE_ADDRESS_UPPER_32_BITS, XBEE_REMOTE_ADDRESS_LOWER_32_BITS, XBEE_NETWORK_16_BIT_ADDRESS, @telemetryBuffer, 25, 0, TRUE)
      lastValuesTime := cnt
    if (cnt-waveFormPeriod) > lastWaveformTime
      sendWaveform(@currentBuffer, "c", ADC_CHANNEL_0_OFFSET)
      sendWaveform(@voltageBuffer, "v", ADC_CHANNEL_1_OFFSET)
      lastWaveformTime := cnt




PUB sendWaveform(pointer, type, theOffset) | i
  longmove(@tempCurrentBuffer, pointer, BUFFER_LENGTH/2)
  repeat i from 0 to 99
    tempCurrentBuffer[i] -= theOffset
  telemetryBuffer[0] := type
  telemetryBuffer[1] := "0"
  byteMove(@telemetryBuffer[2], @tempCurrentBuffer[0], 50)
  xbee.apiArray(XBEE_REMOTE_ADDRESS_UPPER_32_BITS, XBEE_REMOTE_ADDRESS_LOWER_32_BITS, XBEE_NETWORK_16_BIT_ADDRESS, @telemetryBuffer, 52, 0, TRUE)
  waitcnt(clkfreq/30 + cnt)
  byteMove(@telemetryBuffer[2], @tempCurrentBuffer[25], 50)
  xbee.apiArray(XBEE_REMOTE_ADDRESS_UPPER_32_BITS, XBEE_REMOTE_ADDRESS_LOWER_32_BITS, XBEE_NETWORK_16_BIT_ADDRESS, @telemetryBuffer, 52, 0, TRUE)
  waitcnt(clkfreq/30 + cnt)
  byteMove(@telemetryBuffer[2], @tempCurrentBuffer[50], 50)
  xbee.apiArray(XBEE_REMOTE_ADDRESS_UPPER_32_BITS, XBEE_REMOTE_ADDRESS_LOWER_32_BITS, XBEE_NETWORK_16_BIT_ADDRESS, @telemetryBuffer, 52, 0, TRUE)
  waitcnt(clkfreq/30 + cnt)
  telemetryBuffer[1] := 1
  byteMove(@telemetryBuffer[2], @tempCurrentBuffer[75], 50)
  xbee.apiArray(XBEE_REMOTE_ADDRESS_UPPER_32_BITS, XBEE_REMOTE_ADDRESS_LOWER_32_BITS, XBEE_NETWORK_16_BIT_ADDRESS, @telemetryBuffer, 52, 0, TRUE)
  telemetryBuffer[0] := "n"
  xbee.apiArray(XBEE_REMOTE_ADDRESS_UPPER_32_BITS, XBEE_REMOTE_ADDRESS_LOWER_32_BITS, XBEE_NETWORK_16_BIT_ADDRESS, @telemetryBuffer, 1, 0, TRUE)









CON
  SignFlag      = $1                                    'Constats required for floating point routines
  ZeroFlag      = $2
  NaNFlag       = $8

DAT
'--------------------------------------------------------------------------------------------------
'--------------------------------------------------------------------------------------------------
meter_engine  org       0

              mov    	timer,      cnt
              add    	timer,      timerDly

:outer_loop   mov       ptr,        currentBufPtr
              mov       ptr1,       voltageBufPtr
              mov       currentSS,  #0
              mov       voltageSS,  #0

:loop         waitcnt   timer,      timerDly
              rdlong    current,    currentPtr
              rdlong    voltage,    voltagePtr
              wrword    current,    ptr
              wrword    voltage,    ptr1
              sub       current,    currentOffset
              sub       voltage,    voltageOffset
              mov       x,          current
              abs       x,          x
              mov       y,          x
              call      #multiply
              add       currentSS,  y
              mov       x,          voltage
              abs       x,          x
              mov       y,          x
              call      #multiply
              add       voltageSS,  y
              add       ptr,        #2
              add       ptr1,       #2
              cmp       ptr,        buffMax       wc
        if_c  jmp       #:loop


              call      #calculateRMS
              call      #updateEnergy
              jmp       #:outer_loop


:noop         nop
              jmp       #:noop

calculateRMS
              mov       fnumA,      currentSS           'calgulate current RMS for one cycle
              call      #_FFloat
              mov       fnumB,      fBufferLength
              call      #_FDiv
              call      #_FSqr
              mov       fnumB,      currentCor
              call      #_FMul
              mov       fnumB,      currentRMS
              call      #_FAdd
              mov       fnumB,      two
              call      #_FDiv
              mov       currentRMS, fnumA
              wrlong    currentRMS, currentRMSPtr

              mov       fnumA,      voltageSS           'calculate voltage RMS for one cycle
              call      #_FFloat
              mov       fnumB,      fBufferLength
              call      #_FDiv
              call      #_FSqr
              mov       fnumB,      voltageCor
              call      #_FMul
              mov       fnumB,      voltageRMS
              call      #_FAdd
              mov       fnumB,      two
              call      #_FDiv
              mov       voltageRMS, fnumA
              wrlong    voltageRMS, voltageRMSPtr       'we'll just assume 120V for right now
calculateRMS_ret
              ret

updateEnergy
              mov       fnumA,      currentRMS
              mov       fnumB,      voltageRMS
              call      #_FMul
              wrlong    fnumA,      voltAmpsPtr
              mov       fnumB,      sixZero
              call      #_FDiv
              mov       fnumB,      joules
              call      #_FAdd
              mov       joules,     fnumA
              wrlong    joules,     energyPtr
updateEnergy_ret
              ret

fBufferLength long      float(BUFFER_LENGTH)
currentCor    long      0.0075909090909
voltageCor    long      0.0948289578361
two           long      2.0
sixZero       long      60.0



'--------------------------------------------------------------------------------------------------
'--------------------------------------------------------------------------------------------------
current       long      0
voltage       long      0
currentSS     long      0
voltageSS     long      0
buffMax       long      BUFFER_LENGTH*4
timerDly      long      TIME_STEP
currentPtr    long      0
voltagePtr    long      0
currentBufPtr long      0
voltageBufPtr long      0
currentRMSPtr long      0
voltageRMSPtr long      0
energyPtr     long      0
voltAmpsPtr   long      0
timer         long      0
ptr           long      0
ptr1          long      0
currentOffset long      ADC_CHANNEL_0_OFFSET
voltageOffset long      ADC_CHANNEL_1_OFFSET
currentRMS    long      0.0
voltageRMS    long      0.0
joules        long      0.0



'--------------------------------------------------------------------------------------------------
'--------------------------------------------------------------------------------------------------
' Multiply x[15..0] by y[15..0] (y[31..16] must be 0)
' on exit, product in y[31..0]
'
multiply      shl       x,          #16                 'get multiplicand into x[31..16]
              mov       t,          #16                 'ready for 16 multiplier bits
              shr       y,          #1        wc        'get initial multiplier bit into c
:loop   if_c  add       y,          x         wc        'if c set, add multiplicand to product
              rcr       y,          #1        wc        'put next multiplier in c, shift prod.
              djnz      t,          #:loop              'loop until done
multiply_ret  ret                                       'return with product in y[31..0]
'--------------------------------------------------------------------------------------------------
'--------------------------------------------------------------------------------------------------

x             long      0
y             long      0
t             long      0




'--------------------------------------------------------------------------------------------------
'--------------------------------------------------------------------------------------------------
'----------------------------
' addition and subtraction
' fnumA = fnumA +- fnumB
'----------------------------
_FSub                   xor     fnumB, Bit31            ' negate B
                        jmp     #_FAdd                  ' add values

_FAdd                   call    #_Unpack2               ' unpack two variables
          if_c_or_z     jmp     #_FAdd_ret              ' check for NaN or B = 0

                        test    flagA, #SignFlag wz     ' negate A mantissa if negative
          if_nz         neg     manA, manA
                        test    flagB, #SignFlag wz     ' negate B mantissa if negative
          if_nz         neg     manB, manB

                        mov     t1, expA                ' align mantissas
                        sub     t1, expB
                        abs     t1, t1          wc
                        max     t1, #31
              if_nc     sar     manB, t1
              if_c      sar     manA, t1
              if_c      mov     expA, expB

                        add     manA, manB              ' add the two mantissas
                        abs     manA, manA      wc      ' store the absolte value,
                        muxc    flagA, #SignFlag        ' and flag if it was negative

                        call    #_Pack                  ' pack result and exit
_FSub_ret
_FAdd_ret               ret


'----------------------------
' multiplication
' fnumA *= fnumB
'----------------------------
_FMul                   call    #_Unpack2               ' unpack two variables
              if_c      jmp     #_FMul_ret              ' check for NaN

                        xor     flagA, flagB            ' get sign of result
                        add     expA, expB              ' add exponents

                        ' standard method: 404 counts for this block
                        mov     t1, #0                  ' t1 is my accumulator
                        mov     t2, #24                 ' loop counter for multiply (only do the bits needed...23 + implied 1)
                        shr     manB, #6                ' start by right aligning the B mantissa

:multiply               shr     t1, #1                  ' shift the previous accumulation down by 1
                        shr     manB, #1 wc             ' get multiplier bit
              if_c      add     t1, manA                ' if the bit was set, add in the multiplicand
                        djnz    t2, #:multiply          ' go back for more
                        mov     manA, t1                ' yes, that's my final answer.

                        call    #_Pack
_FMul_ret               ret


'----------------------------
' division
' fnumA /= fnumB
'----------------------------
_FDiv                   call    #_Unpack2               ' unpack two variables
          if_c_or_z     mov     fnumA, NaN              ' check for NaN or divide by 0
          if_c_or_z     jmp     #_FDiv_ret

                        xor     flagA, flagB            ' get sign of result
                        sub     expA, expB              ' subtract exponents

                        ' slightly faster division, using 26 passes instead of 30
                        mov     t1, #0                  ' clear quotient
                        mov     t2, #26                 ' loop counter for divide (need 24, plus 2 for rounding)

:divide                 ' divide the mantissas
                        cmpsub  manA, manB      wc
                        rcl     t1, #1
                        shl     manA, #1
                        djnz    t2, #:divide
                        shl     t1, #4                  ' align the result (we did 26 instead of 30 iterations)

                        mov     manA, t1                ' get result and exit
                        call    #_Pack

_FDiv_ret               ret


'------------------------------------------------------------------------------
' square root
' fnumA = sqrt(fnumA)
'------------------------------------------------------------------------------
_FSqr                   call    #_Unpack                 ' unpack floating point value
          if_c_or_z     jmp     #_FSqr_ret               ' check for NaN or zero
                        test    flagA, #signFlag wz      ' check for negative
          if_nz         mov     fnumA, NaN               ' yes, then return NaN
          if_nz         jmp     #_FSqr_ret

                        sar     expA, #1 wc             ' if odd exponent, shift mantissa
          if_c          shl     manA, #1
                        add     expA, #1
                        mov     t2, #29

                        mov     fnumA, #0               ' set initial result to zero
:sqrt                   ' what is the delta root^2 if we add in this bit?
                        mov     t3, fnumA
                        shl     t3, #2
                        add     t3, #1
                        shl     t3, t2
                        ' is the remainder >= delta?
                        cmpsub  manA, t3        wc
                        rcl     fnumA, #1
                        shl     manA, #1
                        djnz    t2, #:sqrt

                        mov     manA, fnumA             ' store new mantissa value and exit
                        call    #_Pack
_FSqr_ret               ret



'------------------------------------------------------------------------------
' fnumA = float(fnumA)
'------------------------------------------------------------------------------
_FFloat                 abs     manA, fnumA     wc,wz   ' get |integer value|
              if_z      jmp     #_FFloat_ret            ' if zero, exit
                        mov     flagA, #0               ' set the sign flag
                        muxc    flagA, #SignFlag        ' depending on the integer's sign
                        mov     expA, #29               ' set my exponent
                        call    #_Pack                  ' pack and exit
_FFloat_ret             ret

'------------------------------------------------------------------------------
' input:   fnumA        32-bit floating point value
'          fnumB        32-bit floating point value
' output:  flagA        fnumA flag bits (Nan, Infinity, Zero, Sign)
'          expA         fnumA exponent (no bias)
'          manA         fnumA mantissa (aligned to bit 29)
'          flagB        fnumB flag bits (Nan, Infinity, Zero, Sign)
'          expB         fnumB exponent (no bias)
'          manB         fnumB mantissa (aligned to bit 29)
'          C flag       set if fnumA or fnumB is NaN
'          Z flag       set if fnumB is zero
' changes: fnumA, flagA, expA, manA, fnumB, flagB, expB, manB, t1
'------------------------------------------------------------------------------
_Unpack2                mov     t1, fnumA               ' save A
                        mov     fnumA, fnumB            ' unpack B to A
                        call    #_Unpack
          if_c          jmp     #_Unpack2_ret           ' check for NaN

                        mov     fnumB, fnumA            ' save B variables
                        mov     flagB, flagA
                        mov     expB, expA
                        mov     manB, manA

                        mov     fnumA, t1               ' unpack A
                        call    #_Unpack
                        cmp     manB, #0 wz             ' set Z flag
_Unpack2_ret            ret


'------------------------------------------------------------------------------
' input:   fnumA        32-bit floating point value
' output:  flagA        fnumA flag bits (Nan, Infinity, Zero, Sign)
'          expA         fnumA exponent (no bias)
'          manA         fnumA mantissa (aligned to bit 29)
'          C flag       set if fnumA is NaN
'          Z flag       set if fnumA is zero
' changes: fnumA, flagA, expA, manA
'------------------------------------------------------------------------------
_Unpack                 mov     flagA, fnumA            ' get sign
                        shr     flagA, #31
                        mov     manA, fnumA             ' get mantissa
                        and     manA, Mask23
                        mov     expA, fnumA             ' get exponent
                        shl     expA, #1
                        shr     expA, #24 wz
          if_z          jmp     #:zeroSubnormal         ' check for zero or subnormal
                        cmp     expA, #255 wz           ' check if finite
          if_nz         jmp     #:finite
                        mov     fnumA, NaN              ' no, then return NaN
                        mov     flagA, #NaNFlag
                        jmp     #:exit2

:zeroSubnormal          or      manA, expA wz,nr        ' check for zero
          if_nz         jmp     #:subnorm
                        or      flagA, #ZeroFlag        ' yes, then set zero flag
                        neg     expA, #150              ' set exponent and exit
                        jmp     #:exit2

:subnorm                shl     manA, #7                ' fix justification for subnormals
:subnorm2               test    manA, Bit29 wz
          if_nz         jmp     #:exit1
                        shl     manA, #1
                        sub     expA, #1
                        jmp     #:subnorm2

:finite                 shl     manA, #6                ' justify mantissa to bit 29
                        or      manA, Bit29             ' add leading one bit

:exit1                  sub     expA, #127              ' remove bias from exponent
:exit2                  test    flagA, #NaNFlag wc      ' set C flag
                        cmp     manA, #0 wz             ' set Z flag
_Unpack_ret             ret


'------------------------------------------------------------------------------
' input:   flagA        fnumA flag bits (Nan, Infinity, Zero, Sign)
'          expA         fnumA exponent (no bias)
'          manA         fnumA mantissa (aligned to bit 29)
' output:  fnumA        32-bit floating point value
' changes: fnumA, flagA, expA, manA
'------------------------------------------------------------------------------
_Pack                   cmp     manA, #0 wz             ' check for zero
          if_z          mov     expA, #0
          if_z          jmp     #:exit1

                        sub     expA, #380              ' take us out of the danger range for djnz
:normalize              shl     manA, #1 wc             ' normalize the mantissa
          if_nc         djnz    expA, #:normalize       ' adjust exponent and jump

                        add     manA, #$100 wc          ' round up by 1/2 lsb

                        addx    expA, #(380 + 127 + 2)  ' add bias to exponent, account for rounding (in flag C, above)
                        mins    expA, Minus23
                        maxs    expA, #255

                        abs     expA, expA wc,wz        ' check for subnormals, and get the abs in case it is
          if_a          jmp     #:exit1

:subnormal              or      manA, #1                ' adjust mantissa
                        ror     manA, #1

                        shr     manA, expA
                        mov     expA, #0                ' biased exponent = 0

:exit1                  mov     fnumA, manA             ' bits 22:0 mantissa
                        shr     fnumA, #9
                        movi    fnumA, expA             ' bits 23:30 exponent
                        shl     flagA, #31
                        or      fnumA, flagA            ' bit 31 sign
_Pack_ret               ret

'-------------------- constant values -----------------------------------------

One                     long    1.0
NaN                     long    $7FFF_FFFF
Minus23                 long    -23
Mask23                  long    $007F_FFFF
Mask29                  long    $1FFF_FFFF
Bit29                   long    $2000_0000
Bit30                   long    $4000_0000
Bit31                   long    $8000_0000
LogTable                long    $C000
ALogTable               long    $D000
SineTable               long    $E000

'-------------------- initialized variables -----------------------------------

'-------------------- local variables -----------------------------------------

ret_ptr                 res     1
t1                      res     1
t2                      res     1
t3                      res     1
t4                      res     1
t5                      res     1
t6                      res     1
t7                      res     1
t8                      res     1

fnumA                   res     1               ' floating point A value
flagA                   res     1
expA                    res     1
manA                    res     1

fnumB                   res     1               ' floating point B value
flagB                   res     1
expB                    res     1
manB                    res     1

              fit       300































DAT
sin_gen       org       0

              mov    	time,       cnt
              add    	time,       timeDly

loop          waitcnt   time,       timeDly
              mov       sin,        angle
              call      #getsin
              sar       sin,        #6
              add       sin,        offset
              wrlong    sin,        par
              djnz      angle,      #loop
              mov       angle,      max_angle
              jmp       #loop

' on entry: sin[12..0] holds angle (0° to just under 360°)
' on exit: sin holds signed value ranging from $0000FFFF ('1') to
' $FFFF0001 ('-1')
'
getcos	      add       sin,        sin_90              'for cosine, add 90°
getsin	      test	sin,        sin_90    wc        'get quadrant 2|4 into c
              test	sin,        sin_180   wz        'get quadrant 3|4 into nz
              negc	sin,        sin	                'if quadrant 2|4, negate offset
              or	sin,        sin_table	        'or in sin table address >> 1
              shl	sin,        #1                  'shift left to get final word address
              rdword    sin,        sin                 'read word sample from $E000 to $F000
              negnz	sin,        sin                 'if quadrant 3|4, negate sample
getsin_ret
getcos_ret    ret	                                '39..54 clocks                                                        '(variance due to HUB sync on RDWORD)
sin_90	      long      $0800
sin_180	      long	$1000
sin_table     long      $E000 >> 1	                'sine table base shifted right
sin	      long 	0



max_angle     long      |< 13 - 1
angle         long      0
timeDly       long      163
offset        long      |< 11
time          res       1

              fit       500


'Permission is hereby granted, free of charge, to any person obtaining a copy
'of this software and associated documentation files (the "Software"), to deal
'in the Software without restriction, including without limitation the rights
'to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
'copies of the Software, and to permit persons to whom the Software is
'furnished to do so, subject to the following conditions:

'The above copyright notice and this permission notice shall be included in
'all copies or substantial portions of the Software.

'THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
'IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
'FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
'AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
'LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
'OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
'THE SOFTWARE.
