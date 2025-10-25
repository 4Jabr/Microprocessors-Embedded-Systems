******************************************************************************************
*                                                                                        *
* Title:          Wave Generator and Digital Clock with 7-Segment Display                *
*                                                                                        *
* Objective:      CMPEN 472 Homework #10                                                 *
*                                                                                        *
* Revision:       V4.11                                                                  *
*                                                                                        *
* Date:	          April 11, 2025                                                         *
*                                                                                        *
* Programmer:     Abdullah Bin Jabr                                                      *
*                                                                                        *
* Institution:    The Pennsylvania State University                                      *
*                 Department of Computer Science and Engineering                         *
*                                                                                        *
* Functionality:  Generates various waveforms while displaying a digital clock           *
*                 - Waveform generation (sawtooth, triangle, square) at multiple rates   *
*                 - 24-hour digital clock runs continuously in background                *
*                 - 7-segment display shows selected time component                      *
*                 - Commands processed through SCI serial communication                  *
*                                                                                        *
* Algorithm:      Uses OC5 timer interrupts at 125 s for waveform generation             *
*                 Uses RTI interrupts at 2.5ms intervals for timekeeping                 *
*                 Command parsing determines wave type and clock functions               *
*                                                                                        *
* Register Usage: A, B: Character processing and wave calculations                       *
*                 X, Y: Counters, string pointers, memory addressing                     *
*                                                                                        *
* Memory Usage:   Data stored in RAM starting at $3000                                   *
*                 Program stored in RAM from $3100                                       *
*                                                                                        *
******************************************************************************************

******************************************************************************************
; Macros and Definitions

            XDEF        Entry     
            ABSENTRY    Entry     

PORTA       EQU         $0000     ; Port A data register
PORTB       EQU         $0001     ; Port B data register (connected to 7-segment display)
DDRA        EQU         $0002     ; Data Direction Register for Port A
DDRB        EQU         $0003     ; Data Direction Register for Port B

SCIBDH      EQU         $00C8     ; Serial port (SCI) Baud Register High
SCIBDL      EQU         $00C9     ; Serial port (SCI) Baud Register Low
SCICR2      EQU         $00CB     ; Serial port (SCI) Control Register 2
SCISR1      EQU         $00CC     ; Serial port (SCI) Status Register 1
SCIDRL      EQU         $00CF     ; Serial port (SCI) Data Register Low

CRGFLG      EQU         $0037     ; Clock and Reset Generator Flags
CRGINT      EQU         $0038     ; Clock and Reset Generator Interrupts
RTICTL      EQU         $003B     ; Real Time Interrupt Control

TIOS        EQU         $0040     ; Timer Input Capture or Output Compare Select
TIE         EQU         $004C     ; Timer Interrupt Enable Register
TSCR1       EQU         $0046     ; Timer System Control Register 1
TSCR2       EQU         $004D     ; Timer System Control Register 2
TFLG1       EQU         $004E     ; Timer Interrupt Flag 1
TC5H        EQU         $005A     ; Timer Channel 5 Register High
TC5L        EQU         $005B     ; Timer Channel 5 Register Low

CR          EQU         $0D       ; ASCII constants
LF          EQU         $0A       
SPACE       EQU         $20       
NULL        EQU         $00       

POINTS_MAX  EQU         2048      ; Total number of points to generate

;*******************************************************
; Variable/data section - Memory allocated at $3000
;*******************************************************
            ORG    $3000          

; Clock variables - Stored in ASCII format for easy display                                    
hourTens    DS.B   1              ; Tens digit of hours (0-2)
hourOnes    DS.B   1              ; Ones digit of hours (0-9)
minTens     DS.B   1              ; Tens digit of minutes (0-5)
minOnes     DS.B   1              ; Ones digit of minutes (0-9)
secTens     DS.B   1              ; Tens digit of seconds (0-5) 
secOnes     DS.B   1              ; Ones digit of seconds (0-9)

; Interrupt counters - Used for timing operations
ctr2p5m     DS.W   1              ; RTI interrupt counter (2.5ms intervals for clock)
ctr125u     DS.W   1              ; OC5 interrupt counter (125us intervals for wave)

; Wave generation variables - Controls waveform output
waveType    DS.B   1              ; 0=none, 1=sawtooth, 2=sawtooth 125Hz, 
                                  ; 3=triangle, 4=square, 5=square 125Hz
waveActive  DS.B   1              ; Status flag: 0=inactive, 1=active
waveValue   DS.B   1              ; Current wave amplitude value (0-255)
waveDir     DS.B   1              ; Direction for triangle wave (0=up, 1=down)
waveCount   DS.B   1              ; Counter for square wave timing
pointCount  DS.W   1              ; Number of points generated out of POINTS_MAX

; Command processing variables
cmdBuffer   DS.B   20             ; Command input buffer
cmdCount    DS.B   1              ; Character count in buffer
inCmd       DS.B   1              ; Command mode flag
cmdEntered  DS.B   1              ; Command ready flag
cmdError    DS.B   1              ; Error flag
errorMsg    DS.B   1              ; Error message flag
displayMode DS.B   1              ; Display mode: 0/1=hour, 2=min, 3=sec

; Utility variables
BUF         DS.B   6              ; Decimal conversion buffer
CTR         DS.B   1              ; Digit counter
newTime     DS.B   6              ; Time setting buffer

;*******************************************************
; Interrupt vector section
            ORG    $FFF0          ; RTI interrupt vector
            DC.W   rtiisr
            
            ORG    $FFE4          ; Timer channel 5 interrupt vector
            DC.W   oc5isr

;*******************************************************
; Code section
            ORG    $3100

            ; Forward declarations for long branch targets
invalidTimeFormat   EQU   *

;***********************************************************************
; Entry point - Initialize system and peripherals
;***********************************************************************
Entry
            LDS    #Entry         ; Initialize stack pointer

            ; Configure I/O ports for the 7-segment display and other outputs
            LDAA   #%11111111     ; Set all PORTA and PORTB pins as outputs
            STAA   DDRA
            STAA   DDRB
            LDAA   #%00000000     ; Clear all outputs initially
            STAA   PORTA
            STAA   PORTB

            ; Setup Serial Communication Interface for terminal interaction
            LDAA   #$0C           ; Enable transmitter and receiver
            STAA   SCICR2         ; Disable SCI interrupts - polling mode used

            LDD    #$0001         ; Set SCI Baud Register = $0001 => 1.5M baud at 24MHz
            STD    SCIBDH         ; Appropriate for simulation environment

            ; Initialize clock to 00:00:00 (ASCII values)
            LDAA   #$30           ; ASCII '0' character
            STAA   hourTens
            STAA   hourOnes
            STAA   minTens
            STAA   minOnes
            STAA   secTens
            STAA   secOnes

            ; Initialize command variables
            CLR    cmdCount       
            CLR    inCmd          
            CLR    cmdEntered     
            CLR    cmdError       
            CLR    errorMsg       
            CLR    displayMode    

            ; Initialize wave generation variables
            CLR    waveType       
            CLR    waveActive     
            CLR    waveValue      
            CLR    waveDir        
            CLR    waveCount      
            CLR    pointCount     
            CLR    pointCount+1   

            ; Initialize Real Time Interrupt for clock
            BSET   RTICTL,%00011001 ; ~2.5ms interval
            BSET   CRGINT,%10000000 ; Enable RTI
            BSET   CRGFLG,%10000000 ; Clear flag

            ; Initialize Timer for wave generation
            BSET   TIOS,%00100000   ; Set channel 5 for Output Compare
            LDAA   #%10000000       ; Enable timer
            STAA   TSCR1
            LDAA   #%00000000       ; No prescaler
            STAA   TSCR2            
            BCLR   TIE,%00100000    ; Disable CH5 interrupt initially

            ; Initialize counters
            LDX    #0
            STX    ctr2p5m          
            STX    ctr125u          

            ; Display initial prompt
            LDX    #promptMsg
            JSR    printmsg
            
            ; Enable interrupts
            CLI                     

;***********************************************************************
; Main program loop - Handles clock updates, user input, and wave generation
;***********************************************************************
mainLoop    
            JSR    updateTime       ; Check and update time if needed
            JSR    checkInput       ; Process any keyboard input from user
            
            LDAA   cmdEntered       ; Check if a command has been entered
            LBEQ    checkWaveStatus  ; If no command, check wave generation status
            
            JSR    processCommand   ; Process the entered command
            CLR    cmdEntered       ; Clear the command entered flag
            
checkWaveStatus
            LDAA   waveActive       ; Check if wave generation is active
            LBEQ    mainLoop         ; If not active, loop back
            
            LDD    pointCount       ; Check if we've generated all points
            CPD    #POINTS_MAX      ; Compare with maximum number of points
            LBLO    mainLoop         ; If not done, continue generation
            
            ; Wave generation complete - clean up and notify user
            CLR    waveActive       ; Mark wave generation as inactive
            BCLR   TIE,%00100000    ; Disable Timer CH5 interrupt
            
            ; Display completion message and new prompt
            JSR    nextline
            LDX    #waveGenIndent   
            JSR    printmsg
            LDX    #waveCompleteMsg
            JSR    printmsg
            
            JSR    nextline
            LDX    #promptMsg
            JSR    printmsg
            
            LBRA    mainLoop         ; Continue main processing loop

;***********************************************************************
; RTI interrupt service routine - Handles clock timing
;***********************************************************************
rtiisr      
            BSET   CRGFLG,%10000000 ; Clear RTI Interrupt Flag
            LDX    ctr2p5m          ; Increment the Real-Time Interrupt counter
            INX                      ; This runs approximately every 2.5ms
            STX    ctr2p5m
            RTI

;***********************************************************************
; Timer OC5 interrupt service routine - Generates waveforms
;***********************************************************************
oc5isr
            ; Schedule next interrupt to maintain precise 125 s timing
            LDD    #3000            ; 125 s interval at 24MHz bus clock
            ADDD   TC5H             ; Add offset to current timer value
            STD    TC5H             ; Set next interrupt time
            
            BSET   TFLG1,%00100000  ; Clear Timer CH5 interrupt flag
            
            ; Check if we've reached maximum points
            LDD    pointCount
            CPD    #POINTS_MAX
            LBHS    oc5done          
            
            ; Increment point counter
            ADDD   #1
            STD    pointCount
            
            ; Generate appropriate wave
            LDAA   waveType
            CMPA   #1
            LBEQ    genSawtooth      
            CMPA   #2
            LBEQ    genSawtooth125   
            CMPA   #3
            LBEQ    genTriangle      
            CMPA   #4
            LBEQ    genSquare        
            CMPA   #5
            LBEQ    genSquare125     
            LBRA    oc5done          
            
genSawtooth
            ; Generate sawtooth wave (0-255)
            LDAA   waveValue
            STAA   waveValue       
            LBRA    sendWaveValueThenInc  
            
genSawtooth125
            ; Generate sawtooth wave at 125Hz (0,4,8,...,252)
            LDD    pointCount
            LDX    #64             ; 64 samples per cycle at 125Hz
            IDIV                   
            
            TFR    D, Y            ; Use remainder to calculate value
            
            TFR    Y, D            
            LSLD                   ; Multiply by 4
            LSLD                   
            SUBB   #04
            STAB   waveValue       
            
            LBRA    sendWaveValue   
            
genTriangle
            ; Generate triangle wave (0-255 up, then 255-0 down)
            LDAA   waveDir
            LBNE    triangleDown     

            ; Triangle going up
            LDAA   waveValue
            STAA   waveValue         
            LBRA    sendWaveThenIncUp

triangleDown
            ; Triangle going down
            LDAA   waveValue
            STAA   waveValue
            LBRA    sendWaveThenDecDown

sendWaveThenIncUp
            LDAB   waveValue        ; Print current value
            CLRA
            JSR    pnum10
            
            LDAA   waveValue        ; Increment value
            INCA
            STAA   waveValue
            CMPA   #255             ; Check if at peak
            LBNE    oc5done

            ; Change direction to down
            LDAA   #1
            STAA   waveDir
            LBRA    oc5done

sendWaveThenDecDown
            LDAB   waveValue        ; Print current value
            CLRA
            JSR    pnum10
            
            LDAA   waveValue        ; Decrement value
            DECA
            STAA   waveValue
            CMPA   #0               ; Check if at bottom
            LBNE    oc5done

            ; Change direction to up
            CLR    waveDir
            LBRA    oc5done
            
genSquare
            ; Generate square wave (0 for 255, 255 for 255)
            LDAB   waveValue        ; Print current value
            CLRA
            JSR    pnum10

            ; Increment counter and check for toggle
            LDAA   waveCount
            INCA
            STAA   waveCount
            CMPA   #255
            LBNE   oc5done

            ; Toggle value and reset counter
            CLR    waveCount
            LDAA   waveValue
            CMPA   #0
            BNE    squareSetLow

            LDAA   #255             ; Change to high
            STAA   waveValue
            LBRA   oc5done

squareSetLow
            CLR    waveValue        ; Change to low
            LBRA   oc5done
            
genSquare125
            ; Generate square wave at 125Hz
            LDAB   waveValue        ; Print current value
            CLRA
            JSR    pnum10

            ; Handle 125Hz frequency
            LDAA   waveCount
            INCA
            STAA   waveCount
            CMPA   #64              ; 64 samples per cycle at 125Hz
            LBNE   oc5done

            ; Toggle value and reset counter
            CLR    waveCount
            LDAA   waveValue
            CMPA   #0
            BNE    square125SetLow

            LDAA   #255             ; Change to high
            STAA   waveValue
            LBRA   oc5done

square125SetLow
            CLR    waveValue        ; Change to low
            LBRA   oc5done
            
sendWaveValue
            ; Print wave value (used by sawtooth125, etc.)
            LDAB   waveValue        
            CLRA                    
            JSR    pnum10           
            LBRA    oc5done         
            
sendWaveValueThenInc
            ; Print wave value then increment for next time
            LDAB   waveValue        
            CLRA                    
            JSR    pnum10           
            
            LDAA   waveValue
            INCA                    
            
            ; Handle 8-bit overflow properly
            CMPA   #0               
            BNE    storeNewValue    
            
storeNewValue
            STAA   waveValue        
            
oc5done     
            RTI

;***********************************************************************
; Update time - Checks if one second has elapsed and updates clock
; This routine is called regularly from the main loop to maintain the clock
;***********************************************************************
updateTime
            PSHA
            PSHB
            PSHX
            
            ; One second equals approximately 400 RTI interrupts at 2.5ms each
            LDX    ctr2p5m
            CPX    #162            ; Using 162 (84x2) because TA's clock was 0.5ticks a second on last HW
            LBLO    doneUpdate     ; Not a full second yet
            
            LDX    #0              ; Reset RTI counter for next second
            STX    ctr2p5m
            
            JSR    incrementTime   ; Update the clock time
            JSR    updateLEDDisplay ; Update the 7-segment display
            
doneUpdate  PULX
            PULB
            PULA
            RTS

;***********************************************************************
; Increment time - Update the clock by 1 second
;***********************************************************************
incrementTime
            PSHA
            
            ; Increment seconds ones
            LDAA   secOnes         
            CMPA   #$39            ; Is it '9'?
            LBNE    incSecOnes      
            
            LDAA   #$30            ; Reset to '0'
            STAA   secOnes         
            
            ; Increment seconds tens
            LDAA   secTens         
            CMPA   #$35            ; Is it '5'?
            LBNE    incSecTens      
            
            LDAA   #$30            ; Reset to '0'
            STAA   secTens         
            
            ; Increment minutes ones
            LDAA   minOnes         
            CMPA   #$39            ; Is it '9'?
            LBNE    incMinOnes      
            
            LDAA   #$30            ; Reset to '0'
            STAA   minOnes         
            
            ; Increment minutes tens
            LDAA   minTens         
            CMPA   #$35            ; Is it '5'?
            LBNE    incMinTens      
            
            LDAA   #$30            ; Reset to '0'
            STAA   minTens         
            
            ; Handle hours (24-hour format)
            LDAA   hourOnes        
            LDAB   hourTens        
            CMPB   #$32            ; Is tens = '2'?
            LBNE    checkHourOnes   
            
            CMPA   #$33            ; Is ones = '3'? (23:59:59)
            LBNE    incHourOnes     
            
            ; Reset to 00:00:00
            LDAA   #$30            
            STAA   hourTens
            STAA   hourOnes
            LBRA    timeUpdated
            
checkHourOnes
            CMPA   #$39            ; Is it '9'?
            LBNE    incHourOnes     
            
            LDAA   #$30            ; Reset to '0'
            STAA   hourOnes        
            
            ; Increment hours tens
            LDAA   hourTens
            INCA
            STAA   hourTens
            LBRA    timeUpdated
            
            ; Increment hours tens
incHourOnes INCA
            STAA   hourOnes
            LBRA    timeUpdated
            ; Increment minute tens
incMinTens  INCA
            STAA   minTens
            LBRA    timeUpdated
            ; Increment minutes ones
incMinOnes  INCA
            STAA   minOnes
            LBRA    timeUpdated
            ; Increment sec tens
incSecTens  INCA
            STAA   secTens
            LBRA    timeUpdated
            ; Increment sec ones
incSecOnes  INCA
            STAA   secOnes
            
timeUpdated
            PULA    ; restore A
            RTS

;***********************************************************************
; Update LED display - Show time component on 7-segment display
;***********************************************************************
updateLEDDisplay
            PSHA
            
            LDAA   displayMode     ; Determine which time component to display
            LBEQ    displayHours    ; Mode 0: hours (default)
            CMPA   #1
            LBEQ    displayHours    ; Mode 1: hours
            CMPA   #2
            LBEQ    displayMinutes  ; Mode 2: minutes
            CMPA   #3
            LBEQ    displaySeconds  ; Mode 3: seconds
            
displayHours
            ; Convert ASCII hours to BCD for 7-segment display
            LDAA   hourTens
            SUBA   #'0'            ; Convert from ASCII to number
            LSLA                   ; Shift to upper nibble
            LSLA
            LSLA
            LSLA
            TAB                    
            LDAA   hourOnes
            SUBA   #'0'            
            ABA                    ; Combine tens and ones
            
            STAA   PORTB           ; Output to 7-segment display
            LBRA    ledDisplayDone
            
displayMinutes
            ; Convert ASCII minutes to BCD for 7-segment display
            LDAA   minTens
            SUBA   #'0'            
            LSLA                   
            LSLA
            LSLA
            LSLA
            TAB                    
            LDAA   minOnes
            SUBA   #'0'            
            ABA                    
            
            STAA   PORTB           
            LBRA    ledDisplayDone
            
displaySeconds
            ; Convert ASCII seconds to BCD for 7-segment display
            LDAA   secTens
            SUBA   #'0'            
            LSLA                   
            LSLA
            LSLA
            LSLA
            TAB                    
            LDAA   secOnes
            SUBA   #'0'            
            ABA                    
            
            STAA   PORTB           
            
ledDisplayDone
            PULA
            RTS

;***********************************************************************
; Check input - Process keyboard input
;***********************************************************************
checkInput
            PSHA
            PSHX
            
            JSR    getchar         ; Check for character input
            CMPA   #0              ; No input?
            LBEQ    inputDone       
            
            LDAB   inCmd           ; Check if already in command mode
            LBNE    handleInput     
            
            ; Start command mode
            LDAB   #1
            STAB   inCmd
            
            ; Initialize command buffer
            LDX    #cmdBuffer
            CLR    0,X             
            CLR    cmdCount        
            
handleInput CMPA   #CR             ; Check for Enter key
            LBEQ    enterPressed
            
            ; Check buffer capacity
            LDAB   cmdCount
            CMPB   #19             ; Max buffer size - 1
            LBHS    inputDone       
            
            ; Add character to buffer
            LDX    #cmdBuffer
            LDAB   cmdCount        
            ABX                    
            STAA   0,X             
            CLR    1,X             ; Null terminate
            INC    cmdCount        
            
            JSR    putchar         ; Echo character
            LBRA    inputDone
            
enterPressed
            LDAA   #1              ; Mark command as entered
            STAA   cmdEntered
            
            JSR    nextline        ; Echo newline
            
inputDone   PULX
            PULA
            RTS

;***********************************************************************
; Process command - Execute entered command
;***********************************************************************
processCommand
            PSHA
            PSHB
            PSHX
            PSHY
            
            LDAA   cmdCount        ; Check for empty command
            LBEQ    cmdDone         
            
            LDX    #cmdBuffer      ; Get first character of command
            LDAA   0,X             
            
            ; Determine command type
            CMPA   #'g'            ; Wave generation command?
            LBEQ    waveGenCmd
            
            CMPA   #'t'            ; Set time command?
            LBEQ    setTimeCmd
            
            CMPA   #'q'            ; Quit command?
            LBEQ    quitCmd
            
            CMPA   #'h'            ; Hour display command?
            LBEQ    hourDisplayCmd
            
            CMPA   #'m'            ; Minute display command?
            LBEQ    minDisplayCmd
            
            CMPA   #'s'            ; Second display command?
            LBEQ    secDisplayCmd
            
            ; Invalid command
            LDAA   #1
            STAA   errorMsg        
            LBRA    invalidCmd
            
;-----------------------------------------------------------------------
; Wave generation commands
;-----------------------------------------------------------------------
waveGenCmd
            ; Check command format
            LDAA   cmdCount
            CMPA   #2              ; Must be at least 2 characters
            LBLO    invalidCmd      
            
            LDAA   1,X             ; Check second character for wave type
            CMPA   #'w'            ; Sawtooth wave?
            LBEQ    checkSawtooth
            CMPA   #'t'            ; Triangle wave?
            LBEQ    triangleWave
            CMPA   #'q'            ; Square wave?
            LBEQ    checkSquare
            LBRA    invalidCmd      
            
checkSawtooth
            ; Check for "gw" or "gw2"
            LDAA   cmdCount
            CMPA   #2              ; Just "gw"?
            LBEQ    sawtoothWave
            
            CMPA   #3              ; Check for "gw2"
            LBNE    invalidCmd      
            
            LDAA   2,X             ; Verify third character is "2"
            CMPA   #'2'
            LBNE    invalidCmd      
            
            ; Setup sawtooth 125Hz wave
            LDAA   #2
            STAA   waveType
            LBRA    startWaveGen
            
sawtoothWave
            ; Setup standard sawtooth wave
            LDAA   #1
            STAA   waveType
            LBRA    startWaveGen
            
triangleWave
            ; Check for exactly "gt"
            LDAA   cmdCount
            CMPA   #2
            LBNE    invalidCmd      
            
            ; Setup triangle wave
            LDAA   #3
            STAA   waveType
            LBRA    startWaveGen
            
checkSquare
            ; Check for "gq" or "gq2"
            LDAA   cmdCount
            CMPA   #2              ; Just "gq"?
            LBEQ    squareWave
            
            CMPA   #3              ; Check for "gq2"
            LBNE    invalidCmd      
            
            LDAA   2,X             ; Verify third character is "2"
            CMPA   #'2'
            LBNE    invalidCmd      
            
            ; Setup square 125Hz wave
            LDAA   #5
            STAA   waveType
            LBRA    startWaveGen
            
squareWave
            ; Setup standard square wave
            LDAA   #4
            STAA   waveType
            LBRA    startWaveGen
            
startWaveGen
            ; Display appropriate message for wave type
            JSR    nextline
            LDX    #waveGenIndent  
            JSR    printmsg
            
            ; Select message based on wave type
            LDAA   waveType
            CMPA   #1              ; Check for basic sawtooth
            LBEQ    sawtoothMsg
            CMPA   #2              ; Check for 125Hz sawtooth
            LBEQ    sawtooth125Msg
            CMPA   #3              ; Check for triangle wave
            LBEQ    triangleMsg
            CMPA   #4              ; Check for basic square wave
            LBEQ    squareMsg
            CMPA   #5              ; Check for 125Hz square wave
            LBEQ    square125Msg
            LBRA    waveGenInit     
            
sawtoothMsg
            LDX    #sawtoothStartMsg    ; Load sawtooth message
            JSR    printmsg             ; Display message
            LBRA    waveGenInit
            
sawtooth125Msg
            LDX    #sawtooth125StartMsg ; Load 125Hz sawtooth message
            JSR    printmsg
            LBRA    waveGenInit
            
triangleMsg
            LDX    #triangleStartMsg    ; Load triangle wave message
            JSR    printmsg
            LBRA    waveGenInit
            
squareMsg
            LDX    #squareStartMsg      ; Load square wave message
            JSR    printmsg
            LBRA    waveGenInit
            
square125Msg
            LDX    #square125StartMsg   ; Load 125Hz square wave message
            JSR    printmsg
            
waveGenInit
            ; Reset all wave generation variables to initial state
            CLR    waveValue       ; Clear amplitude value
            CLR    waveDir         ; Set direction to up (for triangle wave)
            CLR    waveCount       ; Reset counter (for square wave timing)
            LDD    #0
            STD    pointCount      ; Start from first sample point
            
            ; Set wave generation status to active
            LDAA   #1
            STAA   waveActive
            
            ; Configure timer for first interrupt (125 s from now)
            LDD    #3000           ; 3000 timer ticks = 125 s at 24MHz
            ADDD   TC5H            ; Add to current timer value
            STD    TC5H            ; Set output compare register
            
            BSET   TFLG1,%00100000 ; Clear any pending interrupt flag
            BSET   TIE,%00100000   ; Enable timer channel 5 interrupt
            
            LBRA    cmdCleanup      ; Return to command processing
            
;-----------------------------------------------------------------------
; Time command processing
;-----------------------------------------------------------------------
setTimeCmd
            ; Check format: t HH:MM:SS
            LDAA   cmdCount
            CMPA   #9              ; Minimum: t + space + HH:MM:SS
            LBLO    timeFormatError
            
            LDY    #cmdBuffer
            INY                    ; Skip 't'
            
            LDAA   0,Y             ; Check for space
            CMPA   #SPACE
            LBNE    timeFormatError
            INY                    
            
            ; Parse hours
            LDAA   0,Y             ; Hours tens digit
            CMPA   #'0'
            LBLO    timeFormatError
            CMPA   #'2'
            LBHI    timeFormatError
            STAA   newTime         
            INY
            
            LDAA   0,Y             ; Hours ones digit
            CMPA   #'0'
            LBLO    timeFormatError
            CMPA   #'9'
            LBHI    timeFormatError
            
            ; Validate hours (00-23)
            LDAB   newTime         
            CMPB   #'2'
            LBNE    storeHoursOnes  
            
            CMPA   #'4'            ; If tens is '2', ones must be 0-3
            LBHS    timeFormatError
            
storeHoursOnes
            STAA   newTime+1       
            INY
            
            LDAA   0,Y             ; Check for colon
            CMPA   #':'
            LBNE    timeFormatError
            INY
            
            ; Parse minutes
            LDAA   0,Y             ; Minutes tens digit
            CMPA   #'0'
            LBLO    timeFormatError
            CMPA   #'5'
            LBHI    timeFormatError
            STAA   newTime+2       
            INY
            
            LDAA   0,Y             ; Minutes ones digit
            CMPA   #'0'
            LBLO    timeFormatError
            CMPA   #'9'
            LBHI    timeFormatError
            STAA   newTime+3       
            INY
            
            ; Check for optional seconds
            LDAA   0,Y             
            CMPA   #0              ; End of string?
            LBEQ    setTimeWithDefaults 
            CMPA   #':'
            LBNE    timeFormatError
            INY
            
            ; Parse seconds
            LDAA   0,Y             ; Seconds tens digit
            CMPA   #'0'
            LBLO    timeFormatError
            CMPA   #'5'
            LBHI    timeFormatError
            STAA   newTime+4       
            INY
            
            LDAA   0,Y             ; Seconds ones digit
            CMPA   #'0'
            LBLO    timeFormatError
            CMPA   #'9'
            LBHI    timeFormatError
            STAA   newTime+5       
            INY                    

            ; Check for extra characters
            LDAA   0,Y             
            CMPA   #NULL          
            LBNE    timeFormatError
            
setTimeNow  
            ; Set the new time
            LDAA   newTime
            STAA   hourTens
            LDAA   newTime+1
            STAA   hourOnes
            LDAA   newTime+2
            STAA   minTens
            LDAA   newTime+3
            STAA   minOnes
            LDAA   newTime+4
            STAA   secTens
            LDAA   newTime+5
            STAA   secOnes
            
            ; Reset counter
            LDX    #0
            STX    ctr2p5m
            
            LBRA    cmdCleanup
            
setTimeWithDefaults
            ; Set time with default seconds (00)
            LDAA   newTime
            STAA   hourTens
            LDAA   newTime+1
            STAA   hourOnes
            LDAA   newTime+2
            STAA   minTens
            LDAA   newTime+3
            STAA   minOnes
            LDAA   #'0'
            STAA   secTens
            STAA   secOnes
            STAA   newTime+4      
            STAA   newTime+5      
            
            ; Reset counter
            LDX    #0
            STX    ctr2p5m
            
            LBRA    cmdCleanup
            
quitCmd     
            ; Process quit command - stops all activity and enters typewriter mode
            SEI                    ; Disable all interrupts
            BCLR   TIE,%00100000   ; Disable Timer CH5 interrupt specifically
            
            ; Display quit confirmation message
            JSR    nextline
            LDX    #waveGenIndent  ; Add indentation for readability
            JSR    printmsg
            LDX    #quitMsg        ; Display main quit message
            JSR    printmsg
            JSR    nextline
            
            ; Display typewriter mode instructions
            LDX    #waveGenIndent  
            JSR    printmsg
            LDX    #typewriterMsg
            JSR    printmsg
            JSR    nextline
            
            ; Enter infinite typewriter mode loop
typeLoop    JSR    getchar         ; Wait for character input
            TSTA                   ; Test if character was received
            LBEQ    typeLoop       ; If no character, keep waiting
            JSR    putchar         ; Echo character to terminal
            LBRA    typeLoop       ; Repeat forever - no return from here
            
hourDisplayCmd
            ; Set display mode to hours on 7-segment display
            LDAA   cmdCount
            CMPA   #1              ; Verify command is exactly "h"
            LBNE    invalidDisplayCmd ; Branch if wrong length
            
            LDAA   #1              ; Code 1 = hours display mode
            STAA   displayMode     ; Update display mode variable
            LBRA    cmdCleanup      ; Return to command prompt
            
minDisplayCmd
            ; Set display mode to minutes on 7-segment display
            LDAA   cmdCount
            CMPA   #1              ; Verify command is exactly "m"
            LBNE    invalidDisplayCmd ; Branch if wrong length
            
            LDAA   #2              ; Code 2 = minutes display mode
            STAA   displayMode     ; Update display mode variable
            LBRA    cmdCleanup      ; Return to command prompt
            
secDisplayCmd
            ; Set display mode to seconds on 7-segment display
            LDAA   cmdCount
            CMPA   #1              ; Verify command is exactly "s"
            LBNE    invalidDisplayCmd ; Branch if wrong length
            
            LDAA   #3              ; Code 3 = seconds display mode
            STAA   displayMode     ; Update display mode variable
            LBRA    cmdCleanup      ; Return to command prompt
            
invalidDisplayCmd
            ; Handle invalid format for display commands (h, m, s)
            JSR    nextline
            LDX    #errorPrompt    ; Display error prefix
            JSR    printmsg
            LDX    #invalidCmdMsg  ; Show specific display command error message
            JSR    printmsg
            LBRA    cmdCleanup      ; Return to command prompt
            
invalidCmd  
            ; Handle general invalid command error
            JSR    nextline
            LDX    #errorPrompt    ; Display error prefix
            JSR    printmsg
            LDX    #invalidMsg     ; Show generic invalid format message
            JSR    printmsg
            LBRA    cmdCleanup      ; Return to command prompt
            
timeFormatError  
            ; Handle incorrect time format (t HH:MM:SS)
            JSR    nextline
            LDX    #errorPrompt    ; Display error prefix
            JSR    printmsg
            LDX    #invalidTimeMsg ; Show specific time format error message
            JSR    printmsg
            LBRA    cmdCleanup      ; Return to command prompt
            
cmdCleanup  
            ; Reset command processing state for next command
            CLR    inCmd           ; Exit command mode
            LDX    #cmdBuffer      ; Reset command buffer
            CLR    0,X             ; Clear first byte (will terminate string)
            CLR    cmdCount        ; Reset character count
            
            ; Display command prompt for next input
            JSR    nextline        ; Start on new line
            LDX    #promptMsg      ; Show prompt
            JSR    printmsg
            
cmdDone     PULY                   ; Restore registers and return
            PULX
            PULB
            PULA
            RTS

;***********************************************************************
; Print decimal number - Convert 16-bit number to decimal
;***********************************************************************
pnum10      PSHD                  
            PSHX
            PSHY
            CLR    CTR             ; Clear digit counter
            
            LDY    #BUF            ; Setup buffer
pnum10p1    LDX    #10             ; Divide by 10
            IDIV                   ; D / X -> X=quotient, D=remainder
            LBEQ    pnum10p2        ; If quotient is 0, done dividing
            STAB   1,Y+            ; Store remainder
            INC    CTR             ; Count digit
            TFR    X,D             ; Quotient becomes new dividend
            LBRA    pnum10p1        
            
pnum10p2    STAB   1,Y+            ; Store final digit
            INC    CTR             
            
pnum10p3    LDAA   #$30            ; Convert to ASCII
            ADDA   1,-Y            
            JSR    putchar         ; Print digit
            DEC    CTR             
            LBNE    pnum10p3        
            
            JSR    nextline        
            
            PULY
            PULX
            PULD
            RTS

;***********************************************************************
; Utility routines for I/O
;***********************************************************************
printmsg    PSHA                   ; Print null-terminated string
            PSHX
printmsgloop
            LDAA   1,X+            ; Get character, advance pointer
            CMPA   #NULL           ; End of string?
            LBEQ    printmsgdone    
            BSR    putchar         ; Print character
            LBRA    printmsgloop    
printmsgdone
            PULX
            PULA
            RTS

putchar     BRCLR SCISR1,#%10000000,putchar  ; Wait for transmit ready
            STAA  SCIDRL                     ; Send character
            RTS

getchar     BRCLR SCISR1,#%00100000,getchar7 ; Check for received character
            LDAA  SCIDRL                     ; Get character
            RTS
getchar7    CLRA                             ; No character available
            RTS

nextline    PSHA                             ; Print CR+LF
            LDAA  #CR                        
            JSR   putchar
            LDAA  #LF                        
            JSR   putchar
            PULA
            RTS

;*******************************************************
; Data constants - Messages and string literals
;*******************************************************

; Command and prompt messages
promptMsg           DC.B  '> ', $00                 ; Main user prompt
clockPrompt         DC.B  'Clock> ', $00            ; Clock display prompt from HW8 and 9
errorPrompt         DC.B  'Error> ', $00            ; Error message prompt
invalidMsg          DC.B  'Invalid input format', $00
invalidTimeMsg      DC.B  'Invalid time format. Correct example => 00:00:00 to 23:59:59', $00
invalidCmdMsg       DC.B  'Invalid command. ("s" for "second display" and "q" for "quit")', $00
waveGenIndent       DC.B  '       ', $00           ; 7 spaces for indentation from HW8 and9

; Wave type messages
sawtoothStartMsg    DC.B  'sawtooth wave generation ....', $00
sawtooth125StartMsg DC.B  'sawtooth wave 125Hz generation ....', $00
triangleStartMsg    DC.B  'triangle wave generation ....', $00
squareStartMsg      DC.B  'square wave generation ....', $00
square125StartMsg   DC.B  'square wave 125Hz generation ....', $00
waveCompleteMsg     DC.B  'Wave generation complete. 2048 points generated.', $00

; Quit and typewriter mode messages
quitMsg             DC.B  'Typewriter program started.', $00
typewriterMsg       DC.B  'You may type below.', $00

            END
