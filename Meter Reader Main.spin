CON
  _CLKMODE      = XTAL1 + PLL8X
  _XINFREQ      = 5_000_000

  ADC_CLK_PIN   = 7
  ADC_DIN_PIN   = 8
  ADC_DO_PIN    = 9
  ADC_DS_PIN    = 10

  DEBUG_PORT    = 1
  DEBUG_TX_PIN  = 30
  DEBUG_BAUD    = 9600

  XBEE_PORT     = 2
  XBEE_TX_PIN   = 16
  XBEE_RX_PIN   = 17
  XBEE_BAUD     = 57600
  XBEE_REMOTE_ADDRESS_UPPER_32_BITS                     = $00_13_A2_00
  XBEE_REMOTE_ADDRESS_LOWER_32_BITS                     = $40_4B_22_71
  XBEE_NETWORK_16_BIT_ADDRESS                           = $FF_FE

  TELEMETRY_REPORTRING_FREQUENCY                        = 10

  BUFFER_LENGTH = 100

  TIME_STEP     = 13333
  ADC_OFFSET    = 2029




VAR
  LONG channelState[8]
  LONG channelValue[8]
  LONG channelMax[8]
  LONG channelMin[8]
  long sampleBuffer[1024]
  long voltageSampleBuffer[1024]
  LONG rms[2]
  LONG ss
  long ms
  long energy
  long  telemetryTransmitStack[50]
  byte  telemetryBuffer[100]




OBJ
  uarts :       "pcFullDuplexSerial4FC"
  ADC   :       "ADC_INPUT_DRIVER"
  xbee  :       "XBee64Bit"




PUB main
  chan0ptr    := @channelValue[0]
  chan1ptr    := @channelValue[1]
  buffptr     := @sampleBuffer
  chan1rmsptr := @rms[0]
  chan2rmsptr := @rms[1]
  buffMax     := @sampleBuffer[BUFFER_LENGTH]
  ssptr       := @ss
  msptr       := @ms
  energyptr   := @energy

  uarts.init
  uarts.addPort(DEBUG_PORT, UARTS#PINNOTUSED, DEBUG_TX_PIN, UARTS#PINNOTUSED, UARTS#PINNOTUSED, UARTS#DEFAULTTHRESHOLD, UARTS#NOMODE, DEBUG_BAUD)
  uarts.addPort(XBEE_PORT, XBEE_RX_PIN, XBEE_TX_PIN, UARTS#PINNOTUSED, UARTS#PINNOTUSED, UARTS#DEFAULTTHRESHOLD, UARTS#NOMODE, XBEE_BAUD)
  uarts.start
  xbee.initialize(XBEE_PORT)

  ADC.start_pointed(ADC_DO_PIN, ADC_DIN_PIN, ADC_CLK_PIN, ADC_DS_PIN, 8, 2, 12, 1, @channelState, @channelValue, @channelMax, @channelMin)
  'cognew(@sin_gen, @channelValue)
  cognew(@meter_engine, @channelValue)
  cognew(telemetryTransmitLoop, @telemetryTransmitStack)

  'reportBuffer
  reportRMS
  'reportAverage




PUB reportValues | delay
  delay := cnt
  repeat
    uarts.decf(DEBUG_PORT, (channelValue*810+2711)/1000, 4)
    uarts.newline(DEBUG_PORT)
    waitcnt(delay += 80_000_000/3)
  uarts.newline(DEBUG_PORT)
  uarts.newline(DEBUG_PORT)




PUB reportBuffer | i
  waitcnt(cnt + clkfreq/10)
  repeat i from 0 to BUFFER_LENGTH - 1
    uarts.dec(DEBUG_PORT, sampleBuffer[i])
    uarts.newline(DEBUG_PORT)
  uarts.newline(DEBUG_PORT)
  uarts.newline(DEBUG_PORT)





PUB reportRMS
  repeat
    uarts.dec(DEBUG_PORT, rms)
    uarts.newline(1)
    waitcnt(cnt + clkfreq/3)



PUB reportAverage
  repeat
    uarts.dec(DEBUG_PORT, adc.average(0, 100000))
    uarts.newline(1)
    waitcnt(cnt + clkfreq/3)




PUB telemetryTransmitLoop | loopTimer
  loopTimer := cnt
  repeat
    waitcnt(loopTimer += clkfreq/TELEMETRY_REPORTRING_FREQUENCY)
    telemetryBuffer[0] := "r"
    byteMove(@telemetryBuffer[1], @channelValue, 8)
    byteMove(@telemetryBuffer[9], @rms, 8)
    xbee.apiArray(XBEE_REMOTE_ADDRESS_UPPER_32_BITS, XBEE_REMOTE_ADDRESS_LOWER_32_BITS, XBEE_NETWORK_16_BIT_ADDRESS, @telemetryBuffer, 17, 0, TRUE)
















DAT
'--------------------------------------------------------------------------------------------------
'--------------------------------------------------------------------------------------------------
meter_engine  org       0

              mov    	timer,      cnt
              add    	timer,      timerDly

:outer_loop   mov       ptr,        buffptr
              mov       s,          #0
              mov       newaverage, #0
:loop         waitcnt   timer,      timerDly
              rdlong    x,          chan0ptr
              sub       x,          gnd_offset
              wrlong    x,          ptr
              abs       x,          x
              mov       y,          x
              call      #multiply                       'square x
              add       s,          y                   'add square to sums
              wrlong    s,          ssptr
              add       ptr,        #4
              cmp       ptr,        buffMax       wc
        if_c  jmp       #:loop

              mov       arg1,       s
              mov       arg2,       #BUFFER_LENGTH
              call      #divide                         'take mean of squares
              wrlong    r1,         msptr
              mov       y,          r1
              call      #root                           'take root of the mean of squares
              wrlong    x,          chan1rmsptr
              jmp       #:outer_loop

:noop         nop
              jmp       #:noop
'--------------------------------------------------------------------------------------------------
'--------------------------------------------------------------------------------------------------




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




'--------------------------------------------------------------------------------------------------
'--------------------------------------------------------------------------------------------------
'Unsigned INT 32/32 divide into (32;32)  with Kenyan algorithm
'res1 = quotient(I32) of (arg1(I32)/arg2(I32))
'res2 = remainder(I32) of (arg1(I32)/arg2(I32))
divide
                                                        'Prepare working registers
              MOV       r1,         #0                  'Clear 32-bit quuotient
              MOV       r2,         #1                  'Loop counter for divide back steps
                                                        'First round of Kenyan division
:first_loop
              SHL       arg2,       #1                  'Double divisior
              CMP       arg2,       arg1      WZ, WC    'Compare  divisor with divident
                                                        'If divisor is smaller, C is set
                                                        'when they are equal Z is set
IF_C_OR_Z     ADD       r2,         #1                  'IF_C_OR_Z increment counter
IF_C          JMP       #:first_loop                    'IF_C continue first round
                                                        'Second round of Kenyan division
:second_loop
              SHR       arg2,       #1                  'Half divisor
              CMPSUB    arg1,       arg2      WC        'Compare divident with divisor,
                                                        'If divident is greater or equal
                                                        'than divisor, then subtract
                                                        'divisor and set C
              RCL       r1,         #1                  'Double quotient and rotate C into
                                                        'LSB of quotient
              DJNZ      r2,         #:second_loop       'Continue division if steps remained
                                                        'Quotient in r1
divide_ret    ret                                       'Reamainder is what left in arg1
'--------------------------------------------------------------------------------------------------
'--------------------------------------------------------------------------------------------------




'--------------------------------------------------------------------------------------------------
'--------------------------------------------------------------------------------------------------
' Compute square-root of y[31..0] into x[15..0]
'

root          mov       a,          #0                  'reset accumulator
              mov	x,          #0                  'reset root
              mov	t,          #16                 'ready for 16 root bits
:loop         shl	y,          #1        wc        'rotate top two bits of y into accumulator
              rcl       a,          #1
              shl       y,          #1        wc
              rcl       a,          #1
              shl	x,          #2                  'determine next bit of root
              or	x,          #1
              cmpsub    a,          x         wc
              shr       x,          #2
              rcl       x,          #1
              djnz	t,          #:loop              'loop until done 'square root in x[15..0]
root_ret      ret
'--------------------------------------------------------------------------------------------------
'--------------------------------------------------------------------------------------------------




'--------------------------------------------------------------------------------------------------
'--------------------------------------------------------------------------------------------------
a             long      0
r1            long      0
r2            long      0
arg1          long      0
arg2          long      0
x             long      0
y             long      0
t             long      0
s             long      0

buffMax       long      BUFFER_LENGTH*4
timerDly      long      TIME_STEP

temp          long      0
chan0ptr      long      0
chan1ptr      long      0
buffptr       long      0
chan1rmsptr   long      0
chan2rmsptr   long      0
timer         long      0
ssptr         long      0
energyptr     long      0
msptr         long      0
ptr           long      0
average       long      0
newaverage    long      0
oldaverage    long      0
gnd_offset    long      ADC_OFFSET
'--------------------------------------------------------------------------------------------------
'--------------------------------------------------------------------------------------------------

              fit       200































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
