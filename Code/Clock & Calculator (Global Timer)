******************************************************************************************
*                                                                                        *
* Title:          Combined Calculator and 24-Hour Clock with 7-Segment Display           *
*                                                                                        *
* Objective:      CMPEN 472 Homework #9                                                  *
*                                                                                        *
* Revision:       V1.0                                                                   *
*                                                                                        *
* Date:	          April 2, 2025                                                          *
*                                                                                        *
* Programmer:     Abdullah Bin Jabr                                                      *
*                                                                                        *
* Institution:    The Pennsylvania State University                                      *
*                 Department of Computer Science and Engineering                         *
*                                                                                        *
* Functionality:  Combined program that functions as both a calculator and a clock       *
*                 - Calculator processes basic arithmetic operations (+, -, *, /)        *
*                 - Clock keeps real-time and can be adjusted                            *
*                 - 7-segment display shows selected time component                      *
*                 - Commands processed through SCI serial communication                  *
*                                                                                        *
* Algorithm:      Uses RTI interrupts at 2.5ms intervals for timekeeping                 *
*                 Checks inputs to determine calculator vs. clock commands               *
*                 Clock commands start with t, h, m, s, or q                             *
*                 Calculator inputs start with digits and contain operators              *
*                 Both systems share the same input/output infrastructure                *
*                                                                                        *
* Register Usage: A, B: Character processing and calculations                            *
*                 X: Interrupt counter, string pointers, memory addressing               *
*                 Y: Buffer navigation during parsing operations                         *
*                 Stack: Preserves registers during subroutine calls                     *
*                                                                                        *
* Memory Usage:   Data stored in RAM starting at $3000                                   *
*                 Program stored in RAM from $3100                                       *
*                                                                                        *
* Output:         "Tcalc> HH:MM:SS" with real-time updates                               *
*                 "CMD> " for user input (clock commands and calculator expressions)     *
*                 "Error> " for error messages                                           *
*                 Calculator results displayed as "expression=result"                    *
*                 Time component shown on 7-segment LED displays                         *
*                                                                                        *
* Observations:   Integrated program maintains the full functionality of both            *
*                 the calculator and clock systems from HW7 and 8while sharing resources *
*                 Command parsing properly routes inputs to appropriate handler          *
*                 Robust error checking prevents crashes (fool-proof) operations         *
*                                                                                        *
******************************************************************************************


******************************************************************************************
* Export symbols and ASCII definitions                                                   *
******************************************************************************************
            XDEF        Entry        ; export 'Entry' symbol
            ABSENTRY    Entry        ; for assembly entry point

; Macros
PORTA       EQU         $0000
PORTB       EQU         $0001
DDRA        EQU         $0002
DDRB        EQU         $0003

SCIBDH      EQU         $00C8        ; Serial port (SCI) Baud Register H
SCIBDL      EQU         $00C9        ; Serial port (SCI) Baud Register L
SCICR2      EQU         $00CB        ; Serial port (SCI) Control Register 2
SCISR1      EQU         $00CC        ; Serial port (SCI) Status Register 1
SCIDRL      EQU         $00CF        ; Serial port (SCI) Data Register

CRGFLG      EQU         $0037        ; Clock and Reset Generator Flags
CRGINT      EQU         $0038        ; Clock and Reset Generator Interrupts
RTICTL      EQU         $003B        ; Real Time Interrupt Control

CR          EQU         $0D          ; Carriage return, ASCII 'Return' key
LF          EQU         $0A          ; Line feed, ASCII 'next line' character
NULL        EQU         $00          ; Null terminator
SPACE       EQU         $20          ; Space character

;*******************************************************
; Variable/Data Section
            ORG    $3000             ; RAM start defined as $3000

; Time variables                                     
hourTens    DS.B   1                 ; Tens digit of hours (0-2)
hourOnes    DS.B   1                 ; Ones digit of hours (0-9)

minTens     DS.B   1                 ; Tens digit of minutes (0-5)
minOnes     DS.B   1                 ; Ones digit of minutes (0-9)

secTens     DS.B   1                 ; Tens digit of seconds (0-5) 
secOnes     DS.B   1                 ; Ones digit of seconds (0-9)

; RTI interrupt counter
ctr2p5m     DS.W   1                 ; interrupt counter for 2.5 mSec. of time

; Command and display variables
cmdBuffer   DS.B   20                ; Buffer for command input (increased size for calculator)
cmdCount    DS.B   1                 ; Character count in command buffer

inCmd       DS.B   1                 ; Flag: 1 = in command mode, 0 = normal
cmdEntered  DS.B   1                 ; Flag: 1 = command entered (CR received)
cmdError    DS.B   1                 ; Flag: 1 = command error detected
errorMsg    DS.B   1                 ; Error message flag
displayMode DS.B   1                 ; 0= full time, 1=hour, 2=min, 3= sec
calcResult  DS.B   1                 ; Flag: 1 = calculator result to display

; Input processing variables
newTime     DS.B   6                 ; Buffer for new time during set operation

; Calculator variables
isCalcCmd   DS.B   1                 ; Flag: 1 = calculator command, 0 = clock command

FirstStr    DS.B   5                 ; First number string
FirstNum    DS.W   1                 ; First number binary value
FirstLen    DS.B   1                 ; First number length

SecondStr   DS.B   5                 ; Second number string
SecondNum   DS.W   1                 ; Second number binary value
SecondLen   DS.B   1                 ; Second number length

CalcResult  DS.W   1                 ; Calculation result

OutBuffer   DS.B   10                ; Output formatting buffer
DigCount    DS.B   1                 ; Digit count for display

HexKeyCount DS.B   1                 ; Hex numeric count
KeyCount    DS.B   1                 ; Input key count

MathOp      DS.B   1                 ; Math operation code (0=add, 1=subtract, 2=multiply, 3=divide)

MinusFlag   DS.B   1                 ; Negative result flag
OverFlag    DS.B   1                 ; Overflow indicator

CalcExpr    DS.B   20                ; Storage for calculator expression to display

inputPtr    DS.W   1                 ; Pointer to current position in input buffer
outputPtr   DS.W   1                 ; Pointer to current position in output buffer


;*******************************************************
; Interrupt vector section
            ORG    $FFF0             ; RTI interrupt vector setup for the simulator
;            ORG    $3FF0             ; RTI interrupt vector setup for the CSM-12C128 board
            DC.W   rtiisr

;*******************************************************
; Code section

            ORG    $3100
Entry
            LDS    #Entry            ; Initialize the stack pointer

            LDAA   #%11111111        ; Set PORTA and PORTB bit 0,1,2,3,4,5,6,7
            STAA   DDRA              ; All bits of PORTA as output
            STAA   PORTA             ; Set all bits of PORTA
            STAA   DDRB              ; All bits of PORTB as output
            STAA   PORTB             ; Set all bits of PORTB

            LDAA   #$0C              ; Enable SCI port Tx and Rx units
            STAA   SCICR2            ; Disable SCI interrupts

            LDD    #$0001            ; Set SCI Baud Register = $0001 => 1.5M baud at 24MHz
            STD    SCIBDH            ; SCI port baud rate configuration

*******************************************************
* Initialize variables with default values (Start Clock at 00:00:00)
*******************************************************
            
            LDAA   #$30              ; ASCII '0' 
            STAA   hourTens          ; Initialize all time digits to '0'
            STAA   hourOnes
            STAA   minTens  
            STAA   minOnes
            STAA   secTens
            STAA   secOnes

            ; Initialize command and display variables
            CLR    cmdCount          ; Clear command buffer counter
            CLR    inCmd             ; Not in command mode
            CLR    cmdEntered        ; No command entered
            CLR    cmdError          ; No command error
            CLR    errorMsg          ; No error message
            CLR    displayMode       ; Default to full time display
            CLR    calcResult        ; No calculator result to display
            CLR    isCalcCmd         ; Default to clock command

            ; Initialize calculator variables
            CLR    MinusFlag         ; Clear negative result flag
            CLR    OverFlag          ; Clear overflow flag
            LDX    #CalcExpr         ; Clear calculator expression
            CLR    0,X

            ; Print welcome messages
            LDX    #welcomeMsg
            JSR    printmsg
            JSR    nextline
            
            LDX    #instructMsg
            JSR    printmsg
            JSR    nextline
            
            LDX    #calcMsg
            JSR    printmsg
            JSR    nextline
            
            ; Display initial time (00:00:00)
            JSR    displayTimeOnly
            
            ; Initialize Real Time Interrupt
            BSET   RTICTL,%00011001  ; Set RTI: approximately 2.5ms
            BSET   CRGINT,%10000000  ; Enable RTI interrupt
            BSET   CRGFLG,%10000000  ; Clear RTI Interrupt Flag

            LDX    #0
            STX    ctr2p5m           ; Initialize interrupt counter with 0
            CLI                      ; Enable interrupts globally

***********************
* Main program loop
***********************
mainLoop    
            ; Check and update time display if needed
            JSR    updateDisplay     ; Update if 1 second has passed
            
            ; Check for user input
            JSR    checkInput        ; Check for keyboard input
            
            ; Handle command if entered
            LDAA   cmdEntered
            BEQ    mainLoop          ; No command entered, continue loop
            
            ; Process entered command
            JSR    processCommand
            CLR    cmdEntered        ; Clear command entered flag
            
            BRA    mainLoop          ; Continue main loop

;********************************
; Subroutine section
;********************************

;***********RTI interrupt service routine***********  
rtiisr      BSET   CRGFLG,%10000000  ; Clear RTI Interrupt Flag
            LDX    ctr2p5m           ; Increase interrupt count
            INX                      
            STX    ctr2p5m
            RTI
;***********end of RTI interrupt service routine****  

;***************updateDisplay*********************** 
; Check if 1 second has passed and update display if needed
;***************************************************
updateDisplay
            PSHA
            PSHB
            PSHX
            
            ; Check if 1 second has passed (approx. 84 * 2.5ms = 210ms for simulation)
            LDX    ctr2p5m
            CPX    #84               ; From HW8
            BLO    doneUpdate        ; Not yet 1 second

            LDX    #0                ; Reset counter
            STX    ctr2p5m

            ; Update time
            JSR    incrementTime
            
            ; Update display
            JSR    displayTime
            
            ; Update 7-segment LED display
            JSR    updateLEDDisplay

doneUpdate  PULX
            PULB
            PULA
            RTS

;***************incrementTime******************* 
; Increment the time by 1 second
;*********************************************** 
incrementTime
            PSHA
            
            ; Increment seconds
            LDAA   secOnes          ; Get seconds ones
            CMPA   #$39             ; Is it '9'?
            BNE    incSecOnes       ; If not, just increment
            
            ; Reset seconds ones and increment seconds tens
            LDAA   #$30             ; ASCII '0'
            STAA   secOnes          ; Reset ones
            
            LDAA   secTens          ; Get seconds tens
            CMPA   #$35             ; Is it '5'?
            BNE    incSecTens       ; If not, just increment
            
            ; Reset seconds and increment minutes
            LDAA   #$30             ; ASCII '0'
            STAA   secTens          ; Reset tens
            
            ; Increment minutes
            LDAA   minOnes          ; Get minutes ones
            CMPA   #$39             ; Is it '9'?
            BNE    incMinOnes       ; If not, just increment
            
            ; Reset minutes ones and increment minutes tens
            LDAA   #$30             ; ASCII '0'
            STAA   minOnes          ; Reset ones
            
            LDAA   minTens          ; Get minutes tens
            CMPA   #$35             ; Is it '5'?
            BNE    incMinTens       ; If not, just increment
            
            ; Reset minutes and increment hours
            LDAA   #$30             ; ASCII '0'
            STAA   minTens          ; Reset tens
            
            ; Increment hours
            LDAA   hourOnes         ; Get hours ones
            LDAB   hourTens         ; Get hours tens
            CMPB   #$32             ; Is tens = '2'?
            BNE    checkHourOnes    ; If not, check ones normally
            
            ; Hours tens is 2, check if ones is 3 (23 hours)
            CMPA   #$33             ; Is ones = '3'?
            BNE    incHourOnes      ; If not, just increment
            
            ; Time is 23:59:59, reset to 00:00:00!!!
            LDAA   #$30             ; ASCII '0'
            STAA   hourTens
            STAA   hourOnes
            BRA    timeUpdated
            
checkHourOnes
            CMPA   #$39             ; Is it '9'?
            BNE    incHourOnes      ; If not, just increment
            
            ; Reset hours ones and increment hours tens
            LDAA   #$30             ; ASCII '0'
            STAA   hourOnes         ; Reset ones
            
            ; Increment hours tens
            LDAA   hourTens
            INCA
            STAA   hourTens
            BRA    timeUpdated
            
            ; Increment hours ones
incHourOnes
            INCA
            STAA   hourOnes
            BRA    timeUpdated
            
            ; Increment minute tens
incMinTens
            INCA
            STAA   minTens
            BRA    timeUpdated
            
            ; Increment minute ones
incMinOnes
            INCA
            STAA   minOnes
            BRA    timeUpdated
            
            ; Increment second tens
incSecTens
            INCA
            STAA   secTens
            BRA    timeUpdated
            
            ; Increment second ones
incSecOnes
            INCA
            STAA   secOnes
            
timeUpdated
            PULA
            RTS

;***************displayTimeOnly**********************
; Display time without updating it
;**********************************************
displayTimeOnly
            PSHA
            PSHX
            
            ; Display "Tcalc> " prompt
            LDAA   #CR              ; CR (carriage return)
            JSR    putchar
            
            LDX    #tcalcPrompt
            JSR    printmsg
            
            ; Display hours
            LDAA   hourTens
            JSR    putchar
            LDAA   hourOnes
            JSR    putchar
            
            ; Display colon
            LDAA   #$3A             ; ASCII ':'
            JSR    putchar
            
            ; Display minutes
            LDAA   minTens
            JSR    putchar
            LDAA   minOnes
            JSR    putchar
            
            ; Display colon
            LDAA   #$3A             ; ASCII ':'
            JSR    putchar
            
            ; Display seconds
            LDAA   secTens          
            JSR    putchar
            LDAA   secOnes          
            JSR    putchar
            
            PULX
            PULA
            RTS

;***************displayTime************************
; Display full time with any active command or calculator result
;**************************************************
displayTime
            PSHA
            PSHX
            PSHY
            
            JSR    nextline
            ; Display "Tcalc> " prompt with CR first
            LDAA   #CR              ; CR (carriage return)
            JSR    putchar
            
            LDX    #tcalcPrompt
            JSR    printmsg
            
            ; Display hours
            LDAA   hourTens
            JSR    putchar
            LDAA   hourOnes
            JSR    putchar
            
            ; Display colon
            LDAA   #$3A             ; ASCII ':'
            JSR    putchar
            
            ; Display minutes
            LDAA   minTens
            JSR    putchar
            LDAA   minOnes
            JSR    putchar
            
            ; Display colon
            LDAA   #$3A             ; ASCII ':'
            JSR    putchar
            
            ; Display seconds
            LDAA   secTens          
            JSR    putchar
            LDAA   secOnes          
            JSR    putchar
            
            ; Display calculator result if present
            LDAA   calcResult
            BEQ    checkCmdOrError  ; No calculator result
            
            LDAA   #SPACE           ; Add space after time
            JSR    putchar
            
            ; Display calculator expression and result
            LDX    #CalcExpr
            JSR    printmsg
            
            LDX    #eq              ; Display equals sign
            JSR    printmsg
            
            ; Check if negative result
            LDAA   MinusFlag
            BEQ    showCalcResult   ; Not negative
            
            LDX    #minus           ; Show minus sign
            JSR    printmsg
            
showCalcResult
            LDX    #OutBuffer       ; Display result
            JSR    printmsg
            
            CLR    calcResult       ; Clear result flag
            
checkCmdOrError
            ; Display command if active
            LDAA   inCmd
            BEQ    checkError       ; If not in command, check for error
            
            ; Add spacing between time and command
            LDAA   #SPACE
            JSR    putchar
            LDAA   #SPACE
            JSR    putchar
            
            ; Display command prompt
            LDX    #cmdPrompt
            JSR    printmsg
            
            ; Display command buffer
            LDAA   cmdCount
            BEQ    checkError       ; If empty, check for error
            
            LDY    #cmdBuffer
            LDAB   cmdCount         ; Copy count to B to preserve it
displayCmd  LDAA   0,Y              ; Get character from buffer
            JSR    putchar          ; Display it
            INY                     ; Next character
            DECB                    ; Decrement temporary count
            BNE    displayCmd       ; Continue if more characters
            
checkError  ; Display error message if active
            LDAA   errorMsg
            BEQ    displayDone      ; No error
            
            ; Add spacing between time/command and error
            LDAA   #SPACE
            JSR    putchar
            LDAA   #SPACE
            JSR    putchar
            
            ; Display error prompt
            LDX    #errorPrompt
            JSR    printmsg
            
            ; Display appropriate error message
            LDAA   OverFlag
            BNE    showOverflow     ; Overflow error
            
            LDX    #errorIn         ; Invalid input error
            JSR    printmsg
            BRA    clearError
            
showOverflow
            LDX    #errorOvf        ; Overflow error
            JSR    printmsg
            
clearError
            CLR    errorMsg         ; Clear error flag
            CLR    OverFlag         ; Clear overflow flag
            
displayDone PULY
            PULX
            PULA
            RTS

;***************checkInput************************
; Check for keyboard input and handle it whether cmd mode or not
;**************************************************
checkInput
            PSHA
            PSHX
            
            JSR    getchar           ; Check for input
            CMPA   #0                ; No input?
            BEQ    inputDone         ; Done if no input
            
            ; Handle command start if not already in command mode
            LDAB   inCmd
            BNE    handleInput       ; Already in command mode
            
            ; Start command mode
            LDAB   #1
            STAB   inCmd
            
            ; Initialize command buffer
            LDX    #cmdBuffer
            CLR    0,X               ; Clear first byte
            CLR    cmdCount          ; Clear command count
            
handleInput CMPA   #CR               ; Check for Enter key
            BEQ    enterPressed
            
            ; Check buffer capacity before adding
            PSHA                     ; Save character
            
            LDAA   cmdCount          ; Get current character count
            CMPA   #19               ; Check if buffer is almost full (20-1 for null)
            BLO    bufferOK          ; Buffer has space
            
            ; Buffer is at or near capacity, set error flag
            LDAA   #1
            STAA   errorMsg          ; Set error message flag
            PULA                     ; Discard character
            BRA    inputDone
            
bufferOK    PULA                     ; Restore character
            
            ; Add character to buffer
            LDX    #cmdBuffer
            LDAB   cmdCount          ; Get current count
            ABX                      ; Add to pointer
            STAA   0,X               ; Store character
            CLR    1,X               ; Null terminate
            INC    cmdCount          ; Increment count
            BRA    inputDone
            
enterPressed
            ; Set command entered flag
            LDAA   #1
            STAA   cmdEntered
            
            
inputDone   PULX
            PULA
            RTS

;***************processCommand************************
; Process the entered command - decide between calculator and clock commands
;**************************************************
processCommand
            PSHA
            PSHB
            PSHX
            PSHY
            ; Cleaning up using T Q S M H as well
            ; Check if command buffer is empty
            LDAA   cmdCount
            BEQ    cmdDone           ; Empty command, do nothing
            
            ; Check first character to determine command type
            LDX    #cmdBuffer
            LDAA   0,X
            
            ; Convert to lowercase if uppercase
            CMPA   #'A'              ; Check if uppercase
            BLO    checkCommandType  ; Not a letter
            CMPA   #'Z'
            BHI    checkCommandType  ; Not uppercase
            ADDA   #$20              ; Convert to lowercase
            STAA   0,X               ; Store back
            
checkCommandType
            ; Check if it's a clock command (starts with t, h, m, s, q)
            CMPA   #'t'
            BEQ    clockCmd
            CMPA   #'h'
            BEQ    clockCmd
            CMPA   #'m'
            BEQ    clockCmd
            CMPA   #'s'
            BEQ    clockCmd
            CMPA   #'q'
            BEQ    clockCmd
            
            ; Not a clock command, must be calculator input
            ; Check if first character is a digit
            CMPA   #'0'
            BLO    invalidCmd        ; Below '0', invalid
            CMPA   #'9'
            BHI    invalidCmd        ; Above '9', invalid
            
            ; Save the command as a calculator expression
            JSR    copyExprBuffer
            
            ; Process calculator input
            CLR    isCalcCmd
            JSR    calcCommand
            BRA    cmdCleanup
            
clockCmd    ; Process clock command
            LDAA   #1
            STAA   isCalcCmd
            JSR    clockCommand
            BRA    cmdCleanup
            
invalidCmd  ; Handle invalid command
            LDAA   #1
            STAA   errorMsg          ; Set error flag
            
cmdCleanup  ; Clear command buffer and flags
            CLR    inCmd             ; Clear command mode
            LDX    #cmdBuffer
            CLR    0,X               ; Clear first byte
            CLR    cmdCount          ; Clear command count
            JSR    displayTime       ; Force immediate display update
            
cmdDone     PULY
            PULX
            PULB
            PULA
            RTS

;***************copyExprBuffer************************
; Copy the command buffer to the calculator expression buffer
;**************************************************
copyExprBuffer
            PSHA
            PSHB
            PSHX
            PSHY
            
            LDX    #cmdBuffer        ; Source
            LDY    #CalcExpr         ; Destination
            LDAB   cmdCount          ; Character count
            
copyLoop    LDAA   0,X               ; Get character
            STAA   0,Y               ; Store character
            INX                      ; Next source
            INY                      ; Next destination
            DECB                     ; Decrement count
            BNE    copyLoop          ; Continue if more
            
            LDAA   #NULL             ; Null terminator
            STAA   0,Y               ; Terminate string
            
            PULY
            PULX
            PULB
            PULA
            RTS

;***************clockCommand************************
; Process clock commands (t, h, m, s, q)
;**************************************************
clockCommand
            PSHA
            PSHX
            
            ; Get first character to determine command
            LDX    #cmdBuffer
            LDAA   0,X
            
            CMPA   #'t'              ; Set time command?
            BEQ    setTimeCmd
            
            CMPA   #'q'              ; Quit command?
            BEQ    quitCmd
            
            CMPA   #'h'              ; Hour display command?
            BEQ    hourDisplayCmd
            
            CMPA   #'m'              ; Minute display command?
            BEQ    minDisplayCmd
            
            CMPA   #'s'              ; Second display command?
            BEQ    secDisplayCmd
            
            ; Invalid command
            LDAA   #1
            STAA   errorMsg          ; Set error flag
            BRA    clockCmdDone
            
setTimeCmd  ; Process set time command
            ; Format: t HH:MM:SS
            ; Check if command has at least 9 characters (t HH:MM:SS)
            LDAA   cmdCount
            CMPA   #9
            BLO    invalidClockCmd   ; Too short
            
            JSR    parseTimeCommand  ; Parse the time command
            LDAA   errorMsg          ; Check if error occurred during parsing
            BNE    clockCmdDone      ; Error occurred
            BRA    clockCmdDone
            
quitCmd     ; Process quit command
            ; Display quit message
            JSR    nextline
            LDX    #quitMsg
            JSR    printmsg
            JSR    nextline
            
            ; Return to typewriter mode
            LDX    #typewriterMsg
            JSR    printmsg
            JSR    nextline
            
            ; Enter infinite typewriter loop
typeLoop    JSR    getchar           ; Get character
            TSTA                     ; Test if character received
            BEQ    typeLoop          ; If not, continue
            JSR    putchar           ; Echo character
            BRA    typeLoop          ; Continue loop
            
hourDisplayCmd
            ; Set display mode to hours
            LDAA   #1
            STAA   displayMode
            BRA    clockCmdDone
            
minDisplayCmd
            ; Set display mode to minutes
            LDAA   #2
            STAA   displayMode
            BRA    clockCmdDone
            
secDisplayCmd
            ; Set display mode to seconds
            LDAA   #3
            STAA   displayMode
            BRA    clockCmdDone
            
invalidClockCmd
            ; Handle invalid clock command
            LDAA   #1
            STAA   errorMsg          ; Set error flag
            
clockCmdDone
            PULX
            PULA
            RTS

;***************parseTimeCommand************************
; Parse time command of format "t HH:MM:SS" or "t HH:MM"
;********************************************************
parseTimeCommand
            PSHA
            PSHB
            PSHX
            PSHY
            
            LDY    #cmdBuffer
            INY                      ; Skip 't'
            
            ; Check if there's a space after 't'
            LDAA   0,Y
            CMPA   #SPACE
            LBNE    invalidTimeCmd    ; No space
            INY                      ; Skip space
            
            ; Parse hours tens digit
            LDAA   0,Y
            CMPA   #'0'
            LBLO    invalidTimeCmd    ; Below '0'
            CMPA   #'2'
            LBHI    invalidTimeCmd    ; Above '2'
            STAA   newTime           ; Store hours tens
            INY
            
            ; Parse hours ones digit
            LDAA   0,Y
            CMPA   #'0'
            LBLO    invalidTimeCmd    ; Below '0'
            CMPA   #'9'
            LBHI    invalidTimeCmd    ; Above '9'
            
            ; Check if hours is valid (00-23)
            LDAB   newTime           ; Get hours tens
            CMPB   #'2'
            BNE    storeHoursOnes    ; If not 2, any ones digit is valid
            
            ; Hours tens is 2, ones must be 0-3
            CMPA   #'4'
            LBHS    invalidTimeCmd    ; Invalid if >= 4
            
storeHoursOnes
            STAA   newTime+1         ; Store hours ones
            INY
            
            ; Check for colon
            LDAA   0,Y
            CMPA   #':'
            LBNE    invalidTimeCmd    ; Not a colon
            INY
            
            ; Parse minutes tens digit
            LDAA   0,Y
            CMPA   #'0'
            LBLO    invalidTimeCmd    ; Below '0'
            CMPA   #'5'
            LBHI    invalidTimeCmd    ; Above '5'
            STAA   newTime+2         ; Store minutes tens
            INY
            
            ; Parse minutes ones digit
            LDAA   0,Y
            CMPA   #'0'
            LBLO    invalidTimeCmd    ; Below '0'
            CMPA   #'9'
            LBHI    invalidTimeCmd    ; Above '9'
            STAA   newTime+3         ; Store minutes ones
            INY
            
            ; Check for second colon (optional for shorter commands)
            LDAA   0,Y
            CMPA   #0                ; End of string?
            LBEQ    setTimeWithDefaults ; Use default seconds
            CMPA   #':'
            BNE    invalidTimeCmd    ; Not a colon
            INY
            
            ; Parse seconds tens digit
            LDAA   0,Y
            CMPA   #'0'
            BLO    invalidTimeCmd    ; Below '0'
            CMPA   #'5'
            BHI    invalidTimeCmd    ; Above '5'
            STAA   newTime+4         ; Store seconds tens
            INY
            
            ; Parse seconds ones digit
            LDAA   0,Y
            CMPA   #'0'
            BLO    invalidTimeCmd    ; Below '0'
            CMPA   #'9'
            BHI    invalidTimeCmd    ; Above '9'
            STAA   newTime+5         ; Store seconds ones
            INY                      ; Move to next character
            
            LDAA   0,Y               ; Check if there are extra characters
            CMPA   #NULL
            BNE    invalidTimeCmd    ; Extra characters found
            
setTimeNow  ; Set new time
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
            
            ; Reset counter to ensure a clean state
            LDX    #0
            STX    ctr2p5m
            
            BRA    timeParseComplete
            
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
            
            ; Reset counter to ensure a clean state
            LDX    #0
            STX    ctr2p5m
            
            BRA    timeParseComplete
            
invalidTimeCmd
            LDAA   #1
            STAA   errorMsg          ; Set error flag
            
timeParseComplete
            PULY
            PULX
            PULB
            PULA
            RTS

;***************calcCommand************************
; Process calculator input and perform calculation
;**************************************************
calcCommand
            PSHA
            PSHB
            PSHX
            PSHY
            
            ; Initialize pointers for parsing
            LDX    #cmdBuffer
            STX    inputPtr          ; Set input pointer to start of buffer
            
            ; Parse the input
            JSR    parseCalcInput
            
            LDAA   errorMsg          ; Check for errors
            BNE    calcDone          ; Handle errors
            
            ; Process first number
            JSR    processFirstNum
            
            LDAA   errorMsg          ; Check for errors
            BNE    calcDone          ; Handle errors
            
            ; Process second number
            JSR    processSecondNum
            
            LDAA   errorMsg          ; Check for errors
            BNE    calcDone          ; Handle errors
            
            ; Execute operation
            JSR    executeOperation
            
            ; Set calculator result flag
            LDAA   #1
            STAA   calcResult
            
calcDone    PULY
            PULX
            PULB
            PULA
            RTS

;***************parseCalcInput************************
; Parse calculator input expression directly
;****************************************************
parseCalcInput
            PSHA
            PSHB
            PSHX
            PSHY
            
            ; Clear error flag
            CLR    errorMsg
            
            ; Initialize for first number
            LDX    #FirstStr
            STX    outputPtr         ; Set output pointer to FirstStr
            CLR    FirstLen          ; Clear length counter
            
            ; Start parsing - get first number
            JSR    getFirstNumber
            
            LDAA   errorMsg
            BNE    parseExit         ; Exit if error
            
            ; Check if we have a valid first number
            LDAA   FirstLen
            BEQ    invalidExpression
            
            ; Get the operator
            JSR    getOperator
            
            LDAA   errorMsg
            BNE    parseExit         ; Exit if error
            
            ; Initialize for second number
            LDX    #SecondStr
            STX    outputPtr         ; Set output pointer to SecondStr
            CLR    SecondLen         ; Clear length counter
            
            ; Get second number
            JSR    getSecondNumber
            
            ; Check if we have a valid second number
            LDAA   SecondLen
            BEQ    invalidExpression
            
            BRA    parseExit
            
invalidExpression
            LDAA   #1
            STAA   errorMsg
            
parseExit   PULY
            PULX
            PULB
            PULA
            RTS

;***************getFirstNumber************************
; Extract first number digits
;****************************************************
getFirstNumber
            PSHA
            PSHB
            PSHX
            
            LDX    inputPtr          ; Get current input pointer
            
firstDigitLoop
            LDAA   0,X               ; Get character
            
            ; Check if digit
            CMPA   #'0'
            BLO    firstNumDone      ; Less than '0', end of number
            CMPA   #'9'
            BHI    firstNumDone      ; Greater than '9', end of number
            
            ; Store digit and advance
            LDY    outputPtr         ; Get output pointer
            STAA   0,Y               ; Store digit
            INY                      ; Next output position
            STY    outputPtr         ; Update output pointer
            
            INX                      ; Next input position
            STX    inputPtr          ; Update input pointer
            
            INC    FirstLen          ; Count digit
            
            ; Check max length
            LDAA   FirstLen
            CMPA   #4                ; Max 4 digits
            BLO    firstDigitLoop    ; Continue if less than 4
            
            ; Check next character to see if we need to stop
            LDAA   0,X
            CMPA   #'0'              ; Is it a digit?
            BLO    firstNumDone      ; If not, we're done
            CMPA   #'9'
            BHI    firstNumDone      ; If not, we're done
            
            ; Too many digits
            LDAA   #1
            STAA   errorMsg
            BRA    firstNumExit
            
firstNumDone
            ; Terminate the number string
            LDY    outputPtr
            LDAA   #NULL
            STAA   0,Y
            
firstNumExit
            PULX
            PULB
            PULA
            RTS

;***************getOperator************************
; Get the operator character
;****************************************************
getOperator
            PSHA
            PSHB
            PSHX
            
            LDX    inputPtr          ; Get current input position
            LDAA   0,X               ; Get character
            
            ; Check for end of input
            CMPA   #NULL
            BEQ    missingOperator
            CMPA   #CR
            BEQ    missingOperator
            
            ; Identify operator
            CMPA   #'+'
            BEQ    foundAddition
            CMPA   #'-'
            BEQ    foundSubtraction
            CMPA   #'*'
            BEQ    foundMultiplication
            CMPA   #'/'
            BEQ    foundDivision
            
            ; Invalid operator
            LDAA   #1
            STAA   errorMsg
            BRA    opExit
            
missingOperator
            ; Missing operator error
            LDAA   #1
            STAA   errorMsg
            BRA    opExit
            
foundAddition
            LDAA   #0
            STAA   MathOp
            BRA    validOp
            
foundSubtraction
            LDAA   #1
            STAA   MathOp
            BRA    validOp
            
foundMultiplication
            LDAA   #2
            STAA   MathOp
            BRA    validOp
            
foundDivision
            LDAA   #3
            STAA   MathOp
            
validOp     ; Make sure we advance the input pointer
            LDX    inputPtr
            INX                      ; Move past operator
            STX    inputPtr          ; Update input pointer
            
opExit      PULX
            PULB
            PULA
            RTS

;***************getSecondNumber************************
; Extract second number digits
;****************************************************
getSecondNumber
            PSHA
            PSHB
            PSHX
            
            LDX    inputPtr          ; Get current input pointer
            
            ; Check if we're at the end of input without a second number
            LDAA   0,X
            CMPA   #NULL
            BEQ    missingSecondNum
            CMPA   #CR
            BEQ    missingSecondNum
            
secondDigitLoop
            LDX    inputPtr          ; Get current input pointer
            LDAA   0,X               ; Get character
            
            ; Check if end of input
            CMPA   #NULL
            BEQ    secondNumDone
            CMPA   #CR
            BEQ    secondNumDone
            
            ; Check if digit
            CMPA   #'0'
            BLO    secondNumInvalid  ; Less than '0', invalid
            CMPA   #'9'
            BHI    secondNumInvalid  ; Greater than '9', invalid
            
            ; Store digit and advance
            LDY    outputPtr         ; Get output pointer
            STAA   0,Y               ; Store digit
            INY                      ; Next output position
            STY    outputPtr         ; Update output pointer
            
            LDX    inputPtr
            INX                      ; Next input position
            STX    inputPtr          ; Update input pointer
            
            INC    SecondLen         ; Count digit
            
            ; Check max length
            LDAA   SecondLen
            CMPA   #4                ; Max 4 digits
            BLO    secondDigitLoop   ; Continue if less than 4
            
            ; Check next character to see if we should stop
            LDX    inputPtr
            LDAA   0,X
            CMPA   #NULL             ; End of input?
            BEQ    secondNumDone
            CMPA   #CR
            BEQ    secondNumDone
            CMPA   #'0'              ; Is it a digit?
            BLO    secondNumDone     ; If not, we're done
            CMPA   #'9'
            BHI    secondNumDone     ; If not, we're done
            
            ; Too many digits
            LDAA   #1
            STAA   errorMsg
            BRA    secondNumExit
            
missingSecondNum
            ; Missing second number error
            LDAA   #1
            STAA   errorMsg
            BRA    secondNumExit
            
secondNumDone
            ; Terminate the number string
            LDY    outputPtr
            LDAA   #NULL
            STAA   0,Y
            
            BRA    secondNumExit
            
secondNumInvalid
            LDAA   #1
            STAA   errorMsg
            
secondNumExit
            PULX
            PULB
            PULA
            RTS

;***************processFirstNum************************
; Convert first number string to binary
;****************************************************
processFirstNum
            PSHA
            PSHB
            PSHX
            PSHY
            
            LDX    #CalcResult       ; Clear result storage
            CLR    0,X
            CLR    1,X
            
            LDY    #FirstNum
            LDX    #FirstStr
            LDAA   FirstLen
            STAA   DigCount
            JSR    toNumber          ; Convert string to number
            STY    FirstNum
            
            PULY
            PULX
            PULB
            PULA
            RTS

;***************processSecondNum************************
; Convert second number string to binary
;****************************************************
processSecondNum
            PSHA
            PSHB
            PSHX
            PSHY
            
            LDX    #CalcResult       ; Clear temp storage
            CLR    0,X
            CLR    1,X
            
            LDY    #SecondNum
            LDX    #SecondStr
            LDAA   SecondLen
            STAA   DigCount
            JSR    toNumber          ; Convert string to number
            STY    SecondNum
            
            PULY
            PULX
            PULB
            PULA
            RTS

;***************executeOperation************************
; Execute the arithmetic operation
;*******************************************************
executeOperation
            PSHA
            PSHB
            PSHX
            
            LDAA   #$03              ; Initialize error return value
            LDAB   MathOp            ; Get operation code
            CMPB   #$03              ; Check if division (3)
            BHS    checkDivision     ; Handle division separately
            
            CMPB   #$02              ; Check if multiply (2)
            BHS    checkMultiply     ; Handle multiplication
            
            CMPB   #$01              ; Check if subtract (1)
            BHS    checkSubtract     ; Handle subtraction
            
            CMPB   #$00              ; Check if add (0)
            BHS    checkAddition     ; Handle addition
            
            PULX                     ; Restore registers if no match
            PULB
            PULA
            LDAA   #1
            STAA   errorMsg          ; Set error flag
            RTS
            
checkDivision
            PULX                     ; Restore registers
            PULB
            PULA
            JSR    processDivision   ; Process division operation
            RTS
            
checkMultiply
            PULX                     ; Restore registers
            PULB
            PULA
            JSR    processMultiply   ; Process multiplication
            RTS

checkSubtract
            PULX                     ; Restore registers
            PULB
            PULA
            JSR    processSubtract   ; Process subtraction
            RTS
            
checkAddition
            PULX                     ; Restore registers
            PULB
            PULA
            JSR    processAddition   ; Process addition
            RTS

;***************processAddition************************
; Process addition 
;*******************************************************
processAddition
            PSHY                     ; Save Y
            
            LDD    SecondNum         ; Load second number first
            STD    CalcResult        ; Store to result temporarily
            
            LDD    FirstNum          ; Add first number
            ADDD   CalcResult        ; to second number
            BVS    addOverflow       ; Check for signed overflow
            
            STD    CalcResult        ; Store final result
            
            ; Ensure result doesn't exceed 9999
            CPD    #9999
            BHI    addOverflow       ; Overflow if > 9999
            
            ; Convert result to display string
            JSR    toDisplay
            
            PULY                     ; Restore Y
            RTS
            
addOverflow
            PULY                     ; Restore Y
            LDAA   #1
            STAA   OverFlag          ; Set overflow flag
            STAA   errorMsg          ; Set error flag
            RTS

;***************processSubtract************************
; Process subtraction 
;*******************************************************
processSubtract
            PSHY                     ; Save Y
            
            ; Determine if result will be positive or negative
            LDD    SecondNum         ; Load second number
            CPD    FirstNum          ; Compare second to first
            BHS    positiveResult    ; If Second >= First, result is positive with sign
            
            ; Normal subtraction (First > Second)
            LDD    FirstNum          ; Load first number
            SUBD   SecondNum         ; Subtract second number
            
            ; Check for overflow
            BVS    subOverflow       ; Check for signed overflow
            
            STD    CalcResult        ; Store result
            CLR    MinusFlag         ; Clear negative flag (result is positive)
            
            ; Convert result to display string
            JSR    toDisplay
            
            PULY                     ; Restore Y
            RTS
            
positiveResult
            ; Handle subtraction where result is negative
            LDD    SecondNum         ; Load second number
            SUBD   FirstNum          ; Subtract first from second
            
            ; Check for overflow
            BVS    subOverflow       ; Check for signed overflow
            
            STD    CalcResult        ; Store result magnitude
            LDAA   #$01              ; Set negative flag
            STAA   MinusFlag         ; Mark as negative for display
            
            ; Convert result to display string
            JSR    toDisplay
            
            PULY                     ; Restore Y
            RTS
            
subOverflow
            PULY                     ; Restore Y
            LDAA   #1
            STAA   OverFlag          ; Set overflow flag
            STAA   errorMsg          ; Set error flag
            RTS

;***************processMultiply************************
; Process multiplication 
;*******************************************************
processMultiply
            PSHY                     ; Save Y
            
            ; Check for special cases first
            LDD    FirstNum
            PSHD                     ; Save first num
            LDD    SecondNum
            PSHD                     ; Save second num
            
            CPD    #$0000            ; Check if second num is zero
            BEQ    zeroMultResult
            
            PULD                     ; Restore second num
            PULD                     ; Restore first num
            LDY    SecondNum         ; Second operand in Y
            LDD    FirstNum          ; First operand in D
            EMUL                     ; D   Y ? Y:D
            
            ; Check for overflow
            ; First check high word for any non-zero bits
            CPY    #$0000
            BNE    multiplyOverflow
            
            ; Then check if result is > 9999 (max 4-digit number)
            CPD    #10000
            BHS    multiplyOverflow
            
            ; No overflow? -> complete operation!
            STD    CalcResult        ; Store result
            CLR    MinusFlag         ; Ensure no negative flag
            
            ; Convert result to display string
            JSR    toDisplay
            
            PULY                     ; Restore Y
            RTS
            
zeroMultResult
            ; Special case for multiply by zero
            PULD
            PULD
            LDD    #$0000            ; Set result to zero
            STD    CalcResult        ; Store result
            CLR    MinusFlag         ; Ensure no negative flag
            
            ; Convert result to display string
            JSR    toDisplay
            
            PULY                     ; Restore Y
            RTS
            
multiplyOverflow
            PULY                     ; Restore Y
            LDAA   #1
            STAA   OverFlag          ; Set overflow flag
            STAA   errorMsg          ; Set error flag
            RTS

;***************processDivision************************
; Process division 
;*******************************************************
processDivision
            PSHY                     ; Save Y
            PSHY
            
            LDD    SecondNum         ; Get divisor
            PSHD                     ; Save divisor
            TST    0,SP              ; Check low byte
            BNE    divisorNotZero    ; Not zero in low byte
            TST    1,SP              ; Check high byte
            BNE    divisorNotZero    ; Not zero in high byte
            
            ; Division by zero error
            PULX                     ; Clean stack (divisor)
            PULY                     ; Clean stack
            PULY
            LDAA   #1
            STAA   errorMsg          ; Set error flag
            RTS
            
divisorNotZero
            ; Set up division operation
            PULD
            
            TFR    D,X
            LDD    FirstNum          ; Load dividend
            IDIV                     ; D   X ? X = quotient, D = remainder
            TFR    X,D               ; Transfer quotient to D
            STD    CalcResult        ; Store quotient
            CLR    MinusFlag         ; Ensure no negative flag
            
            ; Convert result to display string
            JSR    toDisplay
            
            PULY                     ; Clean temp space
            PULY                     ; Restore Y
            RTS

;***************toNumber************************
; Convert ASCII digits to Bin number
;*********************************************
toNumber    
            PSHA
            PSHB
            PSHX
            
            ; Save X pointer to input string. This was critical, and I missed this in HW7 which is why it wasn't consistent!!!
            PSHX
            
            ; Clear result
            LDX    #CalcResult     ; Initialize result to 0
            CLR    0,X             ; Clear high byte
            CLR    1,X             ; Clear low byte
            
            ; Restore X pointer to input string (EVEN MORE CRUCIAL, AND THIS WAS MY CAUSE OF ERROR BTW Mohammed!)
            PULX
            
            LDAB   DigCount        ; Get digit count

Thousands   CMPB   #$04            ; Four-digit number?
            BNE    Hundreds        ; Try three digits
            DEC    DigCount        ; Process thousands place
            
            LDAA   0,X             ; Get digit from correct position
            SUBA   #$30            ; ASCII to number
            LDAB   #10             ; Multiply by 1000 (100*10)
            MUL                    ; A * 10
            TFR    B, A
            LDAB   #100            ; Second factor
            MUL                    ; A * 100
            STD    CalcResult      ; Store result
            
            INX
            LDAA   0,X
            LDAB   DigCount        ; Update digit count
                
Hundreds    CMPB   #$03            ; Three-digit number?
            BNE    Tens            ; Try two
                
            DEC    DigCount
            
            LDAA   0,X             ; Get digit from correct position
            SUBA   #$30            ; ASCII to number
            LDAB   #100
            MUL                    ; A * 100
            ADDD   CalcResult
            STD    CalcResult      ; Store result
               
            INX
            LDAA   0,X
            LDAB   DigCount        ; Update digit count
                
Tens        CMPB   #$02            ; Two-digit number?
            BNE    Ones            ; Try one digit
               
            DEC    DigCount
            
            LDAA   0,X             ; Get digit from correct position
            SUBA   #$30
            LDAB   #10
            MUL                    ; A * 10
            ADDD   CalcResult
            STD    CalcResult      ; Store result
               
            INX
            LDAA   0,X
            LDAB   DigCount        ; Update digit count
                
Ones        CMPB   #$01            ; One-digit number?
            BNE    convError       ; If not any of these -> Invalid
               
            DEC    DigCount
            
            LDAA   0,X             ; Get digit from correct position
            SUBA   #$30
            LDAB   #1
            MUL                    ; A * 1
            ADDD   CalcResult
            STD    CalcResult      ; Final result
               
            INX                    ; Update pointer
            LDY    CalcResult      ; Return result in Y
            
            PULX
            PULB
            PULA
            RTS

convError   
            LDAA   #1
            STAA   errorMsg          ; Set error flag
            
            PULX
            PULB
            PULA
            RTS

;***************toDisplay************************
; Convert binary number to ASCII digits for display
;*************************************************
toDisplay   
            PSHA
            PSHB
            PSHX
            PSHY
            
            CLR    HexKeyCount       ; Clear digit counter
            LDD    CalcResult        ; Get result
            CPD    #$0000            ; Check for zero
            BEQ    zeroCase
                
            ; Binary to ASCII decimal conversion
            LDY    #OutBuffer        ; Result buffer
divLoop     LDX    #10               ; Divide by 10
            IDIV                     ; D / 10 -> X remainder D
            PSHX                     ; Save quotient
            PSHD                     ; Save remainder
            PULD                     ; Restore remainder (digit)
            STAB   0,Y               ; Store remainder (digit)
            INY
            INC    HexKeyCount       ; Count digits
            PULX                     ; Restore quotient
            TFR    X,D               ; Quotient to D
            CPD    #0                ; Check if done
            BNE    divLoop           ; Continue if not
                
            ; Reverse and convert to ASCII
            LDX    #OutBuffer        ; Get original buffer
            LDAA   HexKeyCount       ; Get digit count
            JSR    reverseBuffer     ; Reverse the buffer
            
            ; Convert to ASCII
            LDX    #OutBuffer        ; Reset buffer pointer
            LDAA   HexKeyCount       ; Get digit count
convAsciiLoop
            LDAB   0,X               ; Get digit
            ADDB   #$30              ; Convert to ASCII
            STAB   0,X               ; Store back
            INX                      ; Next digit
            DECA                     ; Decrement count
            BNE    convAsciiLoop     ; Loop until done
            
            LDAA   #NULL             ; Null terminator
            STAA   0,X               ; Terminate string
            
            PULY
            PULX
            PULB
            PULA
            RTS

reverseBuffer
            PSHA
            PSHB
            PSHX
            PSHY
            
            ; Calculate end position
            LDY    #OutBuffer        ; Start of buffer
            LDAB   HexKeyCount       ; Get count
            ABY                      ; Add to get end position
            DEY                      ; Back up one (to last character)
            
            LDX    #OutBuffer        ; Start of buffer
            
            ; Check if only one digit
            LDAA   HexKeyCount
            CMPA   #1
            BEQ    reverseDone       ; No need to reverse one digit
            
            ; Calculate half point for swapping
            LDAA   HexKeyCount
            LSRA                     ; Divide by 2
            LDAB   #0                ; Counter
            
reverseLoop
            CMPB   HexKeyCount       ; Check if done
            BHS    reverseDone
            
            ; Swap digits
            LDAA   0,X               ; Get digit from start
            PSHA                     ; Save it
            LDAA   0,Y               ; Get digit from end
            STAA   0,X               ; Store at start
            PULA                     ; Restore saved digit
            STAA   0,Y               ; Store at end
            
            INX                      ; Next from start
            DEY                      ; Previous from end
            INCB                     ; Count
            
            LDAA   HexKeyCount
            LSRA                     ; Half of count
            PSHA                     ; Save A on stack
            CMPB   0,SP              ; Compare B with value on stack
            PULA                     ; Restore A from stack
            BLO    reverseLoop       ; Continue if not
            
reverseDone
            PULY
            PULX
            PULB
            PULA
            RTS

zeroCase    
            LDX    #OutBuffer        ; Handle zero
            LDAA   #$30              ; ASCII '0'
            STAA   0,X               ; Store digit
            LDAA   #NULL             ; Null terminator
            STAA   1,X               ; Terminate
            
            PULY
            PULX
            PULB
            PULA
            RTS

;***************updateLEDDisplay************************
; Update 7-segment LED display based on current mode
;******************************************************
updateLEDDisplay
            PSHA
            
            LDAA   displayMode       ; Get current display mode
            BEQ    displayHours      ; Mode 0: default to hours
            CMPA   #1
            BEQ    displayHours      ; Mode 1: hours
            CMPA   #2
            BEQ    displayMinutes    ; Mode 2: minutes
            CMPA   #3
            BEQ    displaySeconds    ; Mode 3: seconds
            
            ; Default to hours
displayHours
            ; Display hours on PORTB using direct BCD representation
            LDAA   hourTens
            SUBA   #'0'              ; Convert from ASCII to number (0-2)
            LSLA                     ; Shift left 4 times to move to upper nibble
            LSLA
            LSLA
            LSLA
            TAB                      ; Store in B temporarily
            LDAA   hourOnes
            SUBA   #'0'              ; Convert from ASCII to number (0-9)
            ABA                      ; Combine with tens digit (now in upper 4 bits)
            
            STAA   PORTB             ; Output to PORTB
            BRA    ledDisplayDone
            
displayMinutes
            ; Display minutes on PORTB using direct BCD representation
            LDAA   minTens
            SUBA   #'0'              ; Convert from ASCII to number (0-5)
            LSLA                     ; Shift left 4 times to move to upper nibble
            LSLA
            LSLA
            LSLA
            TAB                      ; Store in B temporarily
            LDAA   minOnes
            SUBA   #'0'              ; Convert from ASCII to number (0-9)
            ABA                      ; Combine with tens digit (now in upper 4 bits)
            
            STAA   PORTB             ; Output to PORTB
            BRA    ledDisplayDone
            
displaySeconds
            ; Display seconds on PORTB using direct BCD representation
            LDAA   secTens
            SUBA   #'0'              ; Convert from ASCII to number (0-5)
            LSLA                     ; Shift left 4 times to move to upper nibble
            LSLA
            LSLA
            LSLA
            TAB                      ; Store in B temporarily
            LDAA   secOnes
            SUBA   #'0'              ; Convert from ASCII to number (0-9)
            ABA                      ; Combine with tens digit (now in upper 4 bits)
            
            STAA   PORTB             ; Output to PORTB
            
ledDisplayDone
            PULA
            RTS

;***********printmsg***************************
;* Program: Output character string to SCI port, print message
;* Input:   Register X points to ASCII characters in memory
;* Output:  message printed on the terminal connected to SCI port
;**********************************************
printmsg    PSHA                     ; Save registers
            PSHX
printmsgloop LDAA   0,X              ; Pick up an ASCII character
            INX                      ; Advance pointer
            CMPA   #NULL
            BEQ    printmsgdone      ; End of string?
            BSR    putchar           ; If not, print character and continue
            BRA    printmsgloop
printmsgdone PULX 
            PULA
            RTS
;***********end of printmsg********************

;***************putchar************************
;* Program: Send one character to SCI port, terminal
;* Input:   Accumulator A contains an ASCII character, 8bit
;* Output:  Send one character to SCI port, terminal
;**********************************************
putchar     BRCLR SCISR1,#%10000000,putchar   ; Wait for transmit buffer empty
            STAA  SCIDRL                      ; Send a character
            RTS
;***************end of putchar*****************

;****************getchar***********************
;* Program: Input one character from SCI port (terminal/keyboard)
;*             if a character is received, other wise return NULL
;* Input:   none    
;* Output:  Accumulator A containing the received ASCII character
;*          or NULL if no character received
;**********************************************
getchar     BRCLR SCISR1,#%00100000,getchar7
            LDAA  SCIDRL
            RTS
getchar7    CLRA
            RTS
;****************end of getchar**************** 

;****************nextline**********************
nextline    PSHA
            LDAA  #CR                ; Move the cursor to beginning of the line
            JSR   putchar            ; Carriage Return
            LDAA  #LF                ; Move the cursor to next line, Line Feed
            JSR   putchar
            PULA
            RTS
;****************end of nextline***************

; Error messages
errorIn     DC.B   'Invalid input', NULL
errorOvf    DC.B   'Overflow', NULL

; Strings and prompts
tcalcPrompt DC.B   'Tcalc> ', NULL    ; Combined calculator and clock prompt
cmdPrompt   DC.B   'CMD> ', NULL      ; Command prompt
errorPrompt DC.B   'Error> ', NULL    ; Error prompt
eq          DC.B   '=', NULL          ; Equal sign
minus       DC.B   '-', NULL          ; Minus sign
welcomeMsg  DC.B   'Calculator and Digital Clock Program - CMPEN 472', NULL
instructMsg DC.B   'Commands: t HH:MM:SS (set time), h (hours), m (minutes), s (seconds), q (quit)', NULL
calcMsg     DC.B   'Calculator: Enter expressions like 123+456, 78*9, etc.', NULL
quitMsg     DC.B   'Clock and Calculator stopped and Typewrite program started.', NULL
typewriterMsg DC.B 'You may type below.', NULL

            END                      ; End of program
