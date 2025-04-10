/*
*	Digital Clock: This project aims to develop a digital clock 
*    with 3 operating modes: Show the time, stopwatch and adjust the time.
*
*	Copyright (C) [2025] [Digital clock]
*	
*	Developed by:
*	-	Arturo Jim�nez Loaiza 
*	-	Gabriel Vitorino de Andrade  
*	-	Jo�o Matheus Nascimento Dias 
*	-	Manoel Pedro de Aranda Terceiro
*/

;inclusão do arquivo de configuração do microcontrolador atmega328p
.include "m328pdef.inc"

/* The interrupt vector is listed below: */
jmp INIT  ;Interruption RESET

;BUTTONS
jmp MODO  ;Interruption INT0   - button modo
jmp START ;Interruption INT1   - button start
jmp RESET ;Interruption PCINT0 - button reset

;TIME
.org OC1Aaddr
	jmp UPDATE_TIME

;Serial printer
.org 0x28
	;jmp USAR_TX

/* ******************************************* */


/* Set the varibles and registes defines to use at the code */ 
;DEFINES
.def temp          = r16 ; Used only with temporary data
.def display_hour  = r17 ; Exclusive use for modes 1 and 3 (show and adjust time for display)
.def display_crono = r18 ; Exclusive use for mode 2 (show local cronometro)
.def stack		   = r5  ; Exclusive use for stack SREG config
.def mm_time	   = r22 ; Used to represent the minutes of mode 1
.def ss_time	   = r23 ; Used to represent the seconds of mode 1
.def mm_crono	   = r24 ; Used to represent the minutes of mode 2
.def ss_crono	   = r25 ; Used to represent the seocnds of mode 2
.def hour  		   = r19
.def crono 		   = r20
.def delay 		   = r21
.def modo_status   = r26 ; Used to represent the mode of the clock

;.SET



;.EQU
.equ full_input   = 0x00 ; If used all pins of a port will be set like input
.equ full_output  = 0xff ; If used all pins of a port will be set like output
.equ clear		  = 0x00 ; Used to reset hour or crono 
.equ display1	  = 0b00000100 ; Used to power the transistor that will set the unidade dos segundos
.equ display2	  = 0b00001000 ; Used to power the transistor that will set the dezena dos segundos
.equ display3	  = 0b00010000 ; Used to power the transistor that will set the unidade dos minutos
.equ display4	  = 0b00100000 ; Used to power the transistor that will set the dezena dos segundos
.equ displayes	  = display1 | display2 | display3 | display4 ; Use to set only the pins that realy is used
.equ B1			  = 0b00000010 ; MSB of 4 bits that is send to ci4511
.equ B2			  = 0b00000100 ; *
.equ B3			  = 0b00001000 ; *
.equ B4			  = 0b00010000 ; LSB od 4 bits that is send to ci4511
.equ buzzer		  = 0b00100000
.equ CI4511		  = B1 | B2 | B3 | B4	
.equ modo_button  = 0b00000100
.equ start_button = 0b00001000
.equ reset_button = 0b00010000
.equ buttons	  = modo_button | start_button | reset_button

.equ sum_msn	  = (1 << 4) ; Used to sium 

.equ cloclkMHz    = 16
.equ FREQ         = 16000000
.equ BAUD         = 9600


;Storages
show_display: .db display1, display2, display3, display4

/* ******************************************* */

/* Start program and routine and interrupcion implementation */
.org 0x34

INIT:
	;Initial vlaues
		clr temp 
		clr display_hour 
		clr display_crono 
		clr stack 
		clr mm_time 
		clr ss_time
		clr mm_crono
		clr ss_crono
		clr hour 
		clr crono 
		clr delay
		clr modo_status


	;Stack initialization
		ldi temp, low(RAMEND)
		mov stack, temp
		out SPL, stack
		ldi temp, high(RAMEND)
		mov stack, temp
		out SPH, stack

	;Config timer to modo1
		#define CLOCK 16.0e6 ;clock speed
		#define DELAY 1 ;the tima will update at each second
		.equ PRESCALE = 0b100 ;/256 prescale
		.equ PRESCALE_DIV = 256
		.equ WGM = 0b0100 ;Waveform generation mode: CTC
		;you must ensure this value is between 0 and 65535
		.equ TOP = int(0.5 + ((CLOCK/PRESCALE_DIV)*DELAY))
		.if TOP > 65535
		.error "TOP is out of range"
		.endif

	;Config the ports (DDR's) - IO
		ldi temp, CI4511 | buzzer
		out DDRB, temp ; Port B is to CI4511 and buzzer

		ldi temp, displayes
		out DDRC, temp ; Port C is to transistors to select what display will be show the data. 

		ldi temp, buttons
		out DDRD, temp  ; Port D is to receiver the buttons and call the callbacks to system work very well

	;Enable especific interrupt

	; Inicializa UART
		ldi temp, HIGH((FREQ/(16*BAUD)) - 1)
		out UBRR0H, temp
		ldi temp, LOW((FREQ/(16*BAUD)) - 1)
		out UBRR0L, temp
		ldi temp, (1<<TXEN0)
		out UCSR0B, temp
		ldi temp, (1<<UCSZ01)|(1<<UCSZ00)
		out UCSR0C, temp

    ; Timer1 - 1s CTC
		ldi temp, (1<<WGM12)
		sts TCCR1B, temp
		ldi temp, HIGH((FREQ/1024) - 1)
		sts OCR1AH, temp
		ldi temp, LOW((FREQ/1024) - 1)
		sts OCR1AL, temp
		ldi temp, (1<<OCIE1A)|(1<<TOIE1)
		sts TIMSK1, temp
		ldi temp, (1<<CS12)|(1<<CS10) ; Prescaler 1024
		sts TCCR1B, temp

    ; Interrupções externas
		ldi temp, (1<<INT0)|(1<<INT1)
		out EIMSK, temp
		ldi temp, (1<<ISC01)|(1<<ISC11)
		out EICRA, temp
		ldi temp, (1<<PCIE0)
		out PCICR, temp
		ldi temp, (1<<PCINT0)
		out PCMSK0, temp

	sei

MAIN:
	rjmp MAIN ; Infinite loop

;Recebe o argumento da quantidade de delay em ms por r25 (definido por temp)
;DELAY: 
;	ldi r27 , byte3(cloclkMHz * 1000 * temp / 5)
;	ldi r28, HIGH(byte3(cloclkMHz * 1000 * temp / 5))
;	ldi r29, LOW(byte3(cloclkMHz * 1000 * temp / 5))
;
;	sub	r29, 1
;	sbci r28, 0
;	sbci r27, 0
;	brcc pc-3
	
	ret 

FUNC_BUZZER:
    cli ; Critical section - turn the global interruptcion off 

    sbi PORTB, buzzer  ; Turn buzzer on

    ldi temp, 250       ; Await 250ms 
	rcall DELAY

    cbi PORTB, buzzer  ; Turn buzzer off

    sei ; Active the global interruptcion 
    ret

DEBOUMCING:
	cli 

	push stack
	in stack, SREG
	push stack

	

	ldi temp, 100
	rcall DELAY ; Debouncing time


	pop stack
	out SREG, stack
	pop stack

	sei
	ret

KEEP_ALIVE_TIME:
	;TO DO: reativar apenas o timer 1 para que se mantenha a sicronia entre o tempo do microcontrolador e o tempo real para a hora ficar atualizada

UPDATE_TIME:
	ldi temp, 1
	add ss_time, temp ; Incress the second of time
	
	mov temp, ss_time

	rcall GET_LAST_4_BITS

	cpi temp, 0x0a ; Check if the second is 10
	breq RESET_LSN_SECOND ; If the second is less than 10, go to reset the last 4 bits of the second
	reti

	RESET_LSN_SECOND:
		mov temp, ss_time 
		rcall GET_MOST_4_BITS
		ldi temp, sum_msn ; Add 1 to the most significant bit of the second
		add ss_time, temp
	
	mov temp, ss_time

	rcall GET_MOST_4_BITS

	cpi temp, 0x60 ; Check if the second is 60
	breq RESET_MSN_SECOND ; If the second is less than 60, go to reset the last 4 bits of the minute
	reti 

	RESET_MSN_SECOND:
		clr ss_time ; Reset the second to 0
		mov temp, mm_time 
		rcall GET_LAST_4_BITS
		ldi temp, 1 ; Add 1 to the low significant bit of the second
		add mm_time, temp

	mov temp, mm_time

	rcall GET_LAST_4_BITS

	cpi temp, 0x0a ; Check if the second is 10
	breq RESET_LSN_MINUTES ; If the second is less than 10, go to reset the last 4 bits of the second
	reti

	RESET_LSN_MINUTES:
		mov temp, mm_time 
		rcall GET_MOST_4_BITS
		ldi temp, sum_msn ; Add 1 to the most significant bit of the second
		add mm_time, temp
	
	mov temp, mm_time

	rcall GET_MOST_4_BITS

	cpi temp, 0x60 ; Check if the second is 60
	breq RESET_MSN_MINUTES ; If the second is less than 60, go to reset the last 4 bits of the minute
	reti 

	RESET_MSN_MINUTES:
		clr mm_time ; Reset the minutes to 0
		
	reti

GET_LAST_4_BITS:
	andi temp, 0b00001111 ; Get the last 4 bits of the register
	ret

GET_MOST_4_BITS:
	andi temp, 0b11110000 ; Get the most 4 bits of the register
	ret

UPDATE_CRONO:
	;TO DO: implemente de logic to save the crono in the sceg (data memory)
	reti


MODO:
	push stack
	in stack, SREG
	push stack
    
	inc modo_status
	cpi modo_status, 3
	breq NO_RESET_MODE
	ldi modo_status, 0	

	NO_RESET_MODE:
		RCALL FUNC_BUZZER

	pop stack
	out SREG, stack
	pop stack

	reti

START:
	push stack
	in stack, SREG
	push stack

	cpi modo_status, 0
	breq MODO_ONE_START

	cpi modo_status, 1
	breq MODO_TWO_START

	cpi modo_status, 2
	breq MODO_THREE_START

	MODO_ONE_START:
		jmp RETURN_START

	MODO_TWO_START:
		;to do: implement the start/stop of cronomento

	MODO_THREE_START:
		;to do: implement logic to select the display to change the hour (config)

	RETURN_START:
		pop stack
		out SREG, stack
		pop stack
		reti

RESET:
	push stack
	in stack, SREG
	push stack

	cpi modo_status, 0
	breq MODO_ONE_RESET

	cpi modo_status, 1
	breq MODO_TWO_RESET

	cpi modo_status, 2
	breq MODO_THREE_RESET

	MODO_ONE_RESET:
		;to do: to do nothing

	MODO_TWO_RESET:
		;to do: implement the reset of cronomento

	MODO_THREE_RESET:
		;to do: implement the incress of hour (config)

	RETURN_RESET:
		pop stack
		out SREG, stack
		pop stack
		reti
